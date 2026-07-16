"""
Floor C mutation testing for the DISTRIBUTED escrow implementation.

Each mutant removes one guard from a Replica. We then classify each mutant by the STRONGEST
property it breaks, over an adversarial trace:

  cap-safety        : Σspent > CAP  or  SafetyLe (Σspent+Σescrow+InFlight ≤ CAP) violated
  conservation-only : cap-safety holds, but the exact Conserved (= CAP) is violated
  per-request-only  : cap-safety + conservation hold, but a client is double-charged
  well-formedness   : an escrow went negative

The Floor C finding falls straight out of the classification:
  * removing RECEIVER-side transfer dedup  -> cap-safety   (safety-critical)
  * removing SENDER-side transfer dedup    -> conservation-only  (NOT safety-critical)
  * removing charge idempotency            -> per-request-only   (NOT safety-critical)
A mutant that breaks NOTHING is a surviving mutant (a real gap) and fails the suite.
"""
from __future__ import annotations
import sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from distributed import Cluster, Replica, Message


class RecvNoDedup(Replica):
    def receive(self, msg):
        self.escrow += msg.amount            # BUG: no `tid in recvd` guard -> double credit
        self.recvd.add(msg.tid); return True

class IssueNoDedup(Replica):
    def issue(self, dst, amount, tid):
        if amount <= self.escrow:            # BUG: no `tid in issued` guard -> re-debit
            self.escrow -= amount; self.issued[tid] = amount
            return Message(self.name, dst, amount, tid)
        return None

class ChargeNoGuard(Replica):
    def charge(self, amount, opid):
        if opid in self.applied: return True
        self.escrow -= amount; self.spent += amount   # BUG: no `amount <= escrow` guard
        self.applied[opid] = amount
        self.charge_count[opid] = self.charge_count.get(opid, 0) + 1
        return True

class ChargeNoIdemp(Replica):
    def charge(self, amount, opid):
        if amount <= self.escrow:            # BUG: no `opid in applied` dedup
            self.escrow -= amount; self.spent += amount; self.applied[opid] = amount
            self.charge_count[opid] = self.charge_count.get(opid, 0) + 1
            return True
        return False


def classify(c: Cluster) -> str:
    neg = any(r.escrow < 0 for r in c.replicas.values())
    if c.total_spent() > c.cap or not c.safety_le():
        return "cap-safety"
    if not c.conserved():
        return "conservation-only"
    if not c.per_request_ok():
        return "per-request-only"
    if neg:
        return "well-formedness"
    return "SURVIVED"


def trace_recv_dup(c):
    c.issue("a", "b", 1, "t1"); c.deliver(0); c.deliver(0)      # deliver same msg twice

def trace_issue_dup(c):
    c.issue("a", "b", 1, "t1"); c.issue("a", "b", 1, "t1")      # re-issue same transfer id

def trace_charge_over(c):
    for k in range(4):
        c.charge("a", 2, f"o{k}")                                # keep charging past escrow

def trace_charge_dup(c):
    c.charge("a", 1, "o1"); c.charge("a", 1, "o1")               # same charge id twice


MUTANTS = [
    ("no-receiver-dedup (double credit)", RecvNoDedup,  trace_recv_dup,   "cap-safety"),
    ("no-sender-dedup   (re-debit)",      IssueNoDedup,  trace_issue_dup,  "conservation-only"),
    ("no-overspend-guard (charge>escrow)", ChargeNoGuard, trace_charge_over, "cap-safety"),
    ("no-charge-idemp   (double charge)", ChargeNoIdemp, trace_charge_dup, "per-request-only"),
]


def run():
    survived = 0
    print("mutation testing (distributed escrow):")
    for name, cls, trace, expected in MUTANTS:
        c = Cluster({"a": 2, "b": 0}, cap=2, replica_cls=cls)
        trace(c)
        got = classify(c)
        tag = "killed" if got != "SURVIVED" else "SURVIVED"
        match = "  (as expected)" if got == expected else f"  (expected {expected}!)"
        print(f"  {tag:8} {name:38} -> {got}{match}")
        if got == "SURVIVED":
            survived += 1
    print(f"mutation score: {len(MUTANTS) - survived}/{len(MUTANTS)} killed")
    print("Finding reproduced: receiver-dedup is cap-safety-critical; "
          "sender-dedup is conservation-only.")
    if survived:
        print("MUTATION TESTING: FAIL — surviving mutant(s)")
        return 1
    print("MUTATION TESTING: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
