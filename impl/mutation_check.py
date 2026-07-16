"""
Floor B mutation testing for the escrow reference.

Each mutant injects one semantic fault. A mutant is KILLED if some check catches it:
  * the conserved-quantity / safety invariant (self._check -> InvariantViolation), OR
  * the separate per-request idempotency property (per_request_ok()).

Honest, load-bearing distinction this surfaces: the cap-safety invariant catches faults that
CREATE or MISPLACE budget (no dedup on delivery, no overspend guard, no debit on send, no
transfer-idempotency). It does NOT catch a missing CHARGE-idempotency guard — double-applying
one charge id preserves Σspent+Σescrow and keeps Σspent ≤ CAP, so it is caught only by the
separate per-request check. A surviving mutant (no check catches it) is a real gap and fails.
"""
from __future__ import annotations
import sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from escrow import EscrowService, InvariantViolation


class MutNoDeliverDedup(EscrowService):
    def deliver(self, idx):
        m = self.net[idx]
        self.escrow[m.dst] += m.amount           # BUG: no receiver-side dedup
        self.recvd.add(m.tid)
        self._check(); return True

class MutNoChargeGuard(EscrowService):
    def charge(self, replica, amount, opid):
        self.escrow[replica] -= amount            # BUG: no `amount <= escrow` guard
        self.spent[replica] += amount
        self.applied[opid] = amount
        self.charge_count[opid] = self.charge_count.get(opid, 0) + 1
        self._check(); return True

class MutNoSendDebit(EscrowService):
    def send_transfer(self, src, dst, amount, tid):
        if tid in self.sent: return False
        self.sent[tid] = (dst, amount)            # BUG: does not debit src's escrow
        from escrow import Message
        self.net.append(Message(dst=dst, amount=amount, tid=tid))
        self._check(); return True

class MutNoChargeIdemp(EscrowService):
    def charge(self, replica, amount, opid):
        if amount <= self.escrow[replica]:        # BUG: no `opid in applied` dedup
            self.escrow[replica] -= amount
            self.spent[replica] += amount
            self.applied[opid] = amount
            self.charge_count[opid] = self.charge_count.get(opid, 0) + 1
            self._check(); return True
        return False

class MutNoSendIdemp(EscrowService):
    def send_transfer(self, src, dst, amount, tid):
        if amount <= self.escrow[src]:            # BUG: no `tid in sent` dedup
            self.escrow[src] -= amount
            self.sent[tid] = (dst, amount)
            from escrow import Message
            self.net.append(Message(dst=dst, amount=amount, tid=tid))
            self._check(); return True
        return False


def trace_deliver_dup(s):
    s.send_transfer("a", "b", 1, "t1"); s.deliver(0); s.deliver(0)

def trace_charge_over(s):
    s.charge("b", 1, "op1")                        # b has no escrow

def trace_send(s):
    s.send_transfer("a", "b", 1, "t1")

def trace_charge_dup(s):
    s.charge("a", 1, "op1"); s.charge("a", 1, "op1")

def trace_send_dup(s):
    s.send_transfer("a", "b", 1, "t1"); s.send_transfer("a", "b", 1, "t1")


MUTANTS = [
    ("no-deliver-dedup   (double credit)",  MutNoDeliverDedup, trace_deliver_dup),
    ("no-overspend-guard (charge > escrow)", MutNoChargeGuard,  trace_charge_over),
    ("no-debit-on-send   (creates budget)",  MutNoSendDebit,    trace_send),
    ("no-charge-idemp    (double charge)",   MutNoChargeIdemp,  trace_charge_dup),
    ("no-send-idemp      (double debit)",    MutNoSendIdemp,    trace_send_dup),
]


def run():
    survived = 0
    print("mutation testing (escrow reference):")
    for name, cls, trace in MUTANTS:
        s = cls(["a", "b"], cap=3, genesis="a")
        killer = None
        try:
            trace(s)
        except InvariantViolation:
            killer = "conserved/safety invariant"
        if killer is None and not s.per_request_ok():
            killer = "per-request idempotency check"
        if killer is None:
            print(f"  SURVIVED  {name}   <-- GAP: no check caught this mutant")
            survived += 1
        else:
            print(f"  killed    {name}   by {killer}")
    total = len(MUTANTS)
    print(f"mutation score: {total - survived}/{total} mutants killed")
    if survived:
        print("MUTATION TESTING: FAIL — surviving mutants indicate a verification gap")
        return 1
    print("MUTATION TESTING: OK — every injected fault is caught")
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
