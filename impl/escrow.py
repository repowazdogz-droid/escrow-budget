"""
Floor B — centralised REFERENCE implementation of the escrow budget service.

A single object simulates all replicas plus the (unreliable) network, mirroring the TLA+
model in spec/EscrowBudget.tla but with ARBITRARY non-negative amounts (a strengthening; the
invariant is identical in shape). Every mutating operation re-establishes the SINGLE SOURCE
OF TRUTH — the conserved quantity — before returning:

    Σ spent[i]  +  Σ escrow[i]  +  InFlight   =   CAP        (Conserved)
    Σ spent[i]  ≤  CAP                                       (Safety, a corollary)

The reference REFUSES to enter a state violating these (self._check raises). This makes it a
faithful oracle for later model-based / property-based tests and fault injection (Floor E).

Honest scoping (discovered while implementing — see SCOPE.md):
  * The Conserved/Safety invariant is sensitive to: the local no-overspend guard, transfer
    (receiver-side) idempotency, atomic debit-before-send, and no-budget-creation. Violate any
    and Conserved (or non-negativity) breaks.
  * It is NOT sensitive to CHARGE idempotency: double-applying one charge id moves budget from
    escrow to spent, which preserves Σspent+Σescrow and keeps Σspent ≤ CAP. Charge idempotency
    protects a SEPARATE per-request property (no double-charge), tracked here via `applied` and
    checked separately (per_request_ok / test), not folded into the cap-safety theorem.
"""
from __future__ import annotations
from dataclasses import dataclass, field


class InvariantViolation(AssertionError):
    """Raised when a mutating operation would break Conserved or Safety."""


@dataclass
class Message:
    dst: str
    amount: int
    tid: str


class EscrowService:
    def __init__(self, replicas, cap: int, genesis: str, strict: bool = True):
        replicas = list(replicas)
        assert genesis in replicas, "genesis must be a replica"
        assert cap >= 0, "CAP must be non-negative"
        self.replicas = replicas
        self.cap = cap
        self.escrow = {r: 0 for r in replicas}
        self.escrow[genesis] = cap                 # genesis holds the whole cap
        self.spent = {r: 0 for r in replicas}
        self.applied: dict[str, int] = {}          # opid -> amount of an AUTHORISED charge
        self.sent: dict[str, tuple[str, int]] = {} # tid -> (dst, amount) once debited
        self.recvd: set[str] = set()               # tids credited at destination
        self.net: list[Message] = []               # in-flight messages (retained => duplicates)
        self.charge_count: dict[str, int] = {}      # opid -> times the debit path ran (per-request audit)
        self.strict = strict
        self._check()

    # ---- conserved quantity (single source of truth) ----
    def inflight(self) -> int:
        return sum(amt for tid, (_dst, amt) in self.sent.items() if tid not in self.recvd)

    def total_spent(self) -> int:
        return sum(self.spent.values())

    def total_escrow(self) -> int:
        return sum(self.escrow.values())

    def conserved(self) -> int:
        return self.total_spent() + self.total_escrow() + self.inflight()

    def _check(self) -> None:
        if not self.strict:
            return
        if self.conserved() != self.cap:
            raise InvariantViolation(f"Conserved broken: {self.conserved()} != CAP {self.cap}")
        if self.total_spent() > self.cap:
            raise InvariantViolation(f"Safety broken: Σspent {self.total_spent()} > CAP {self.cap}")
        if any(v < 0 for v in self.escrow.values()):
            raise InvariantViolation("negative escrow")
        if any(v < 0 for v in self.spent.values()):
            raise InvariantViolation("negative spent")

    # ---- operations (mirror the TLA+ actions) ----
    def charge(self, replica: str, amount: int, opid: str) -> bool:
        """Authorise `amount` at `replica` from its local escrow. Idempotent: a duplicate of an
        AUTHORISED opid is a no-op returning True. A rejected charge is NOT recorded (a later
        retry may succeed after a refill). No coordination."""
        assert amount >= 0
        if opid in self.applied:
            return True                             # already authorised — idempotent
        if amount <= self.escrow[replica]:
            self.escrow[replica] -= amount
            self.spent[replica] += amount
            self.applied[opid] = amount
            self.charge_count[opid] = self.charge_count.get(opid, 0) + 1
            self._check()
            return True
        return False                                # rejected (insufficient local escrow)

    def send_transfer(self, src: str, dst: str, amount: int, tid: str) -> bool:
        """Debit `amount` from `src` and put it in flight to `dst`. Idempotent per tid: a
        re-send of the same tid does not re-debit."""
        assert amount >= 0
        if tid in self.sent:
            return False                            # already sent — idempotent debit
        if amount <= self.escrow[src]:
            self.escrow[src] -= amount
            self.sent[tid] = (dst, amount)
            self.net.append(Message(dst=dst, amount=amount, tid=tid))
            self._check()
            return True
        return False

    def deliver(self, idx: int) -> bool:
        """Credit the in-flight message at net[idx]. Idempotent per tid: duplicate delivery is
        ignored. The message is RETAINED (so it can be re-delivered = duplicate)."""
        msg = self.net[idx]
        if msg.tid in self.recvd:
            return False                            # duplicate delivery — idempotent no-op
        self.escrow[msg.dst] += msg.amount
        self.recvd.add(msg.tid)
        self._check()
        return True

    def drop(self, idx: int) -> bool:
        """Message loss: drop an in-flight message. Its amount stays counted in InFlight
        (permanently lost capacity) — safety preserved."""
        self.net.pop(idx)
        self._check()
        return True

    # ---- separate per-request property (NOT the cap-safety theorem) ----
    def per_request_ok(self) -> bool:
        """Each charge id debited at most once (no double-charge of a client)."""
        return all(c <= 1 for c in self.charge_count.values())
