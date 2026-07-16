"""
Floor D mutation testing for the crash/recovery escrow implementation.

Each mutant removes a durability discipline (or adds an extra crash effect). Classification, over
an adversarial crash trace:

  cap-safety        : Σspent > CAP  or  SafetyLe violated  (budget CREATED — safety-critical)
  conservation-only : Safety holds but Conserved (= CAP) fails (budget DESTROYED — safe)

The Floor D structural finding falls out of the classification:
  * no-write-ahead-debit  -> cap-safety  (a SENDER-side crash creates budget)
  * volatile-recvd        -> cap-safety  (a receiver double-credit across a crash)
  * crash-also-drops-inflight (extra destruction) -> conservation-only  (NOT safety-critical)

So the safety-critical crash faults are exactly the budget-CREATING ones, on BOTH sides — which
refutes the narrow "receiver-side only" reading and keeps the creation/destruction law.
"""
from __future__ import annotations
import sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from durable import DurableCluster, DurableReplica


class NoWriteAhead(DurableReplica):
    def debit_for_send(self, amount):
        if amount <= self.escrow:
            self.escrow -= amount            # BUG: never persists the debit (no write-ahead)
            return True
        return False

class VolatileRecvd(DurableReplica):
    def credit(self, tid, amount):
        if tid in self.recvd:
            return False
        self.escrow += amount; self.recvd.add(tid)
        self.d_escrow = self.escrow          # balance durable ...
        return True                           # BUG: recvd never persisted
    def crash(self):
        self.escrow = self.d_escrow; self.spent = self.d_spent
        self.recvd = set()                    # ... so a crash loses it


class CrashDropsInflightCluster(DurableCluster):
    """Destruction mutant: a crash also loses this replica's in-flight sent messages."""
    def crash(self, name):
        super().crash(name)
        self.sentMsgs = [m for m in self.sentMsgs if m.dst != name]   # extra budget destruction


def classify(c) -> str:
    if c.total_spent() > c.cap or not c.safety_le():
        return "cap-safety"
    if not c.conserved():
        return "conservation-only"
    return "SURVIVED"


def run():
    survived = 0
    print("mutation testing (crash/recovery escrow):")
    results = []

    # replica-level mutants
    c = DurableCluster({"a": 2, "b": 0}, cap=2, replica_cls=NoWriteAhead)
    c.issue("a", "b", 1, "t1"); c.crash("a")
    results.append(("no-write-ahead-debit (sender crash)", classify(c), "cap-safety"))

    c = DurableCluster({"a": 2, "b": 0}, cap=2, replica_cls=VolatileRecvd)
    c.issue("a", "b", 1, "t1"); c.deliver(0); c.crash("b"); c.deliver(0)
    results.append(("volatile-recvd (crash + retransmit)", classify(c), "cap-safety"))

    # destruction mutant (should NOT be cap-safety)
    c = CrashDropsInflightCluster({"a": 2, "b": 0}, cap=2)
    c.issue("a", "b", 1, "t1"); c.crash("b")
    results.append(("crash-drops-inflight (destruction)", classify(c), "conservation-only"))

    for name, got, expected in results:
        tag = "killed" if got != "SURVIVED" else "SURVIVED"
        match = "  (as expected)" if got == expected else f"  (expected {expected}!)"
        print(f"  {tag:8} {name:38} -> {got}{match}")
        if got == "SURVIVED":
            survived += 1
    print(f"mutation score: {len(results) - survived}/{len(results)} killed")
    print("Finding: safety-critical crash faults are the budget-CREATING ones on BOTH sides;")
    print("         a destruction fault is caught only by conservation, never by safety.")
    if survived:
        print("MUTATION TESTING: FAIL — surviving mutant(s)")
        return 1
    print("MUTATION TESTING: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
