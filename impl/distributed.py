"""
Floor C — DISTRIBUTED message-passing escrow budget service (executable).

Replicas hold local escrow and exchange transfers over an unreliable Network that may reorder,
duplicate, and drop messages. Arbitrary non-negative amounts. Explicit message identifiers.
Sender- and receiver-side transfer idempotency are each independently switchable so the
executable can reproduce the model-checked finding:

    receiver idempotency  =>  SafetyLe  (Σspent + Σescrow + InFlight ≤ CAP)   [the cap theorem]
    receiver AND sender    =>  Conserved (… = CAP)                            [no budget lost]

A sender-side non-idempotent retry only DESTROYS budget (the sum drops), so it breaks Conserved
but NOT SafetyLe. A receiver-side duplicate CREATES budget, breaking SafetyLe. See spec/
EscrowBudgetC.tla and SCOPE.md.
"""
from __future__ import annotations
from dataclasses import dataclass


@dataclass(frozen=True)
class Message:
    src: str
    dst: str
    amount: int
    tid: str


class Replica:
    def __init__(self, name, escrow=0, *, sender_idempotent=True, receiver_idempotent=True):
        self.name = name
        self.escrow = escrow
        self.spent = 0
        self.applied: dict[str, int] = {}   # charge opid -> amount (per-request idempotency)
        self.charge_count: dict[str, int] = {}
        self.issued: dict[str, int] = {}    # tid -> amount this replica has debited
        self.recvd: set[str] = set()        # tids credited here
        self.sender_idempotent = sender_idempotent
        self.receiver_idempotent = receiver_idempotent

    def charge(self, amount: int, opid: str) -> bool:
        assert amount >= 0
        if opid in self.applied:
            return True
        if amount <= self.escrow:
            self.escrow -= amount
            self.spent += amount
            self.applied[opid] = amount
            self.charge_count[opid] = self.charge_count.get(opid, 0) + 1
            return True
        return False

    def issue(self, dst: str, amount: int, tid: str):
        """Debit local escrow and return a Message, or None if rejected. If sender-idempotent,
        a re-issue of a known tid does not re-debit (returns None)."""
        assert amount >= 0
        if self.sender_idempotent and tid in self.issued:
            return None
        if amount <= self.escrow:
            self.escrow -= amount
            self.issued[tid] = amount
            return Message(self.name, dst, amount, tid)
        return None

    def receive(self, msg: Message) -> bool:
        """Credit an incoming transfer. If receiver-idempotent, credit at most once per tid."""
        if self.receiver_idempotent and msg.tid in self.recvd:
            return False
        self.escrow += msg.amount
        self.recvd.add(msg.tid)
        return True

    def per_request_ok(self) -> bool:
        return all(c <= 1 for c in self.charge_count.values())


class Cluster:
    """Replicas + an unreliable network. Tracks the global conserved quantity as the single
    source of truth. `check()` asserts exactly what the current idempotency configuration is
    supposed to guarantee — nothing stronger."""

    def __init__(self, replicas: dict[str, int], cap: int, *,
                 sender_idempotent=True, receiver_idempotent=True, replica_cls=Replica):
        self.cap = cap
        self.sender_idempotent = sender_idempotent
        self.receiver_idempotent = receiver_idempotent
        self.replicas = {n: replica_cls(n, e, sender_idempotent=sender_idempotent,
                                        receiver_idempotent=receiver_idempotent)
                         for n, e in replicas.items()}
        self.net: list[Message] = []          # in-flight messages (retained => duplicable)
        self.tid_amount: dict[str, int] = {}  # nominal amount per transfer id (first issue)
        self.received_tids: set[str] = set()  # union of all replicas' recvd

    # ---- global conserved quantity ----
    def total_escrow(self) -> int:
        return sum(r.escrow for r in self.replicas.values())

    def total_spent(self) -> int:
        return sum(r.spent for r in self.replicas.values())

    def inflight(self) -> int:
        # nominal amount of each transfer id sent-but-not-yet-credited (each id counted once)
        return sum(a for tid, a in self.tid_amount.items() if tid not in self.received_tids)

    def quantity(self) -> int:
        return self.total_spent() + self.total_escrow() + self.inflight()

    def safety_le(self) -> bool:
        return self.quantity() <= self.cap

    def conserved(self) -> bool:
        return self.quantity() == self.cap

    def per_request_ok(self) -> bool:
        return all(r.per_request_ok() for r in self.replicas.values())

    def check(self) -> None:
        """Assert precisely the guarantee the configuration provides (never more)."""
        assert self.total_spent() <= self.cap, f"CAP breached: Σspent {self.total_spent()} > {self.cap}"
        if self.receiver_idempotent:
            assert self.safety_le(), f"SafetyLe broken: {self.quantity()} > {self.cap}"
        if self.sender_idempotent and self.receiver_idempotent:
            assert self.conserved(), f"Conserved broken: {self.quantity()} != {self.cap}"

    # ---- operations ----
    def charge(self, name: str, amount: int, opid: str) -> bool:
        return self.replicas[name].charge(amount, opid)

    def issue(self, src: str, dst: str, amount: int, tid: str):
        msg = self.replicas[src].issue(dst, amount, tid)
        if msg is not None:
            self.tid_amount.setdefault(tid, amount)   # nominal amount fixed at first issue
            self.net.append(msg)
        return msg

    def deliver(self, idx: int) -> bool:
        msg = self.net[idx]                           # message retained (duplicate delivery ok)
        ok = self.replicas[msg.dst].receive(msg)
        if ok:
            self.received_tids.add(msg.tid)
        return ok

    def drop(self, idx: int) -> Message:
        return self.net.pop(idx)                       # loss (its amount stays 'in flight')
