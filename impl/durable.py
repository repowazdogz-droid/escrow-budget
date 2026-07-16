"""
Floor D — DISTRIBUTED escrow with crash / recovery / durable vs volatile state.

Each replica has volatile CURRENT state (escrow, spent, recvd) and a DURABLE snapshot
(d_escrow, d_spent, d_recvd). persist() checkpoints current->durable; crash() reverts
current<-durable (all un-persisted work lost). The network (`sentMsgs`) is monotonic and
external — a crash does not un-send a message — and deliver() may fire on any sent message any
number of times, which models reorder / duplication / loss / PARTITION (delay) / HEALING (later
delivery) / RETRANSMISSION AFTER RECOVERY (deliver an old message post-crash).

Two durability disciplines are switchable so their necessity is testable:
  debit_durable_before_send : write-ahead the escrow debit before emitting the transfer.
  recvd_durable             : the receiver dedup set survives a crash.

Mirrors spec/EscrowBudgetD.tla. The conserved quantity is the single source of truth; check()
asserts exactly what the configuration guarantees (Σspent ≤ CAP always; SafetyLe when
disciplined) — never more.
"""
from __future__ import annotations
from dataclasses import dataclass


@dataclass(frozen=True)
class Message:
    dst: str
    tid: str


class DurableReplica:
    def __init__(self, name, escrow, *, debit_durable_before_send=True, recvd_durable=True):
        self.name = name
        self.escrow = escrow; self.spent = 0; self.recvd: set[str] = set()      # volatile
        self.d_escrow = escrow; self.d_spent = 0; self.d_recvd: set[str] = set()  # durable
        self.ddbs = debit_durable_before_send
        self.rd = recvd_durable

    def charge(self, amount: int) -> bool:
        if amount <= self.escrow:
            self.escrow -= amount; self.spent += amount
            return True
        return False

    def debit_for_send(self, amount: int) -> bool:
        if amount <= self.escrow:
            self.escrow -= amount
            if self.ddbs:
                self.d_escrow = self.escrow          # write-ahead: debit is durable before emit
            return True
        return False

    def credit(self, tid: str, amount: int) -> bool:
        if tid in self.recvd:
            return False                             # dedup: already credited
        self.escrow += amount; self.recvd.add(tid)
        self.d_escrow = self.escrow                  # credited balance is durable
        if self.rd:
            self.d_recvd = set(self.recvd)           # dedup set durable
        return True

    def persist(self) -> None:
        self.d_escrow = self.escrow; self.d_spent = self.spent
        if self.rd:
            self.d_recvd = set(self.recvd)

    def crash(self) -> None:
        self.escrow = self.d_escrow; self.spent = self.d_spent
        self.recvd = set(self.d_recvd) if self.rd else set()


class DurableCluster:
    def __init__(self, replicas: dict[str, int], cap: int, *,
                 debit_durable_before_send=True, recvd_durable=True, replica_cls=DurableReplica):
        self.cap = cap
        self.disciplined = debit_durable_before_send and recvd_durable
        self.replicas = {n: replica_cls(n, e,
                                        debit_durable_before_send=debit_durable_before_send,
                                        recvd_durable=recvd_durable)
                         for n, e in replicas.items()}
        self.sentMsgs: list[Message] = []            # monotonic, external (survives crashes)
        self.amtOf: dict[str, int] = {}

    # ---- conserved quantity ----
    def total_escrow(self): return sum(r.escrow for r in self.replicas.values())
    def total_spent(self):  return sum(r.spent for r in self.replicas.values())

    def inflight(self) -> int:
        credited = set().union(*(r.recvd for r in self.replicas.values())) if self.replicas else set()
        sent_tids = {m.tid for m in self.sentMsgs}
        return sum(self.amtOf[t] for t in sent_tids - credited)

    def quantity(self):    return self.total_spent() + self.total_escrow() + self.inflight()
    def safety_le(self):   return self.quantity() <= self.cap
    def conserved(self):   return self.quantity() == self.cap

    def check(self) -> None:
        assert self.total_spent() <= self.cap, f"CAP breached: Σspent {self.total_spent()} > {self.cap}"
        if self.disciplined:
            assert self.safety_le(), f"SafetyLe broken: {self.quantity()} > {self.cap}"

    # ---- operations ----
    def charge(self, name, amount):
        return self.replicas[name].charge(amount)

    def issue(self, src, dst, amount, tid):
        if tid in self.amtOf:                        # unique-id protocol: no re-issue here
            return False
        if self.replicas[src].debit_for_send(amount):
            self.amtOf[tid] = amount
            self.sentMsgs.append(Message(dst=dst, tid=tid))
            return True
        return False

    def deliver(self, idx):                          # may be called repeatedly / after a crash
        msg = self.sentMsgs[idx]
        return self.replicas[msg.dst].credit(msg.tid, self.amtOf[msg.tid])

    def persist(self, name): self.replicas[name].persist()
    def crash(self, name):   self.replicas[name].crash()
