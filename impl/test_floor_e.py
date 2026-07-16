"""
Floor E — gate-sized checks (the full 10,000-execution run is `python3 impl/fault_harness.py`).

Bundles: the differential/conformance check, a moderate hostile-harness run on the disciplined
protocol, a teeth check (broken protocol must be caught), and a targeted falsification probe
showing "Safety holds while Bound fails" is reachable ONLY in a broken protocol (consistent with
Bound being sufficient-not-necessary — not a theory break).
"""
from __future__ import annotations
import sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
import pytest
from spec_model import run as differential_run
from fault_harness import run_disciplined, run_broken
from durable import DurableCluster


def test_differential_conforms_to_tla():
    assert differential_run() == 0                 # 66 == 66 distinct states, all invariants hold


def test_hostile_harness_disciplined_holds():
    run_disciplined(max_examples=1500, steps=40)   # no CertificateViolation == certificate held


def test_harness_has_teeth_broken_is_caught():
    with pytest.raises(AssertionError):
        run_broken(max_examples=3000)


def test_bound_can_fail_while_safety_holds_in_broken():
    """Falsification probe 'Safety holds while Bound fails': reachable in the BROKEN (volatile
    recvd) protocol. Bound (A ≤ CAP) fails the moment budget is created; Safety (Σspent ≤ CAP)
    still holds until the excess is spent. This CONFIRMS Bound is a stricter leading indicator
    than Safety (sufficient, not necessary) — it does not falsify the frozen theory."""
    c = DurableCluster({"a": 1, "b": 0}, cap=1, recvd_durable=False)
    c.issue("a", "b", 1, "t1")
    c.deliver(0)                                   # credit b (recvd volatile)
    c.crash("b")                                   # lose recvd; balance durable -> tid re-opens
    A = c.quantity()
    assert A > c.cap                               # Bound FAILS (A = 2 > CAP = 1)
    assert c.total_spent() <= c.cap                # Safety still HOLDS (nothing spent yet)
    assert all(r.escrow >= 0 for r in c.replicas.values())  # WF holds (this is a Bound break)


def test_conservation_only_mutant_survives_safety_harness_by_design():
    """Honest mutation result: a mutant that breaks ONLY conservation (destroys extra budget)
    SURVIVES a safety-focused harness — correctly, because it does not violate WF/Bound/Safety.
    It is a real bug, caught only by a conservation check. This is why the mutation SUITES check
    conservation separately; the safety harness deliberately does not."""
    from distributed import Cluster, Replica

    class DestroyOnDeliver(Replica):
        def receive(self, msg):
            ok = super().receive(msg)
            if ok and self.escrow >= 1:
                self.escrow -= 1                   # BUG: extra destruction (conservation, not safety)
            return ok

    c = Cluster({"a": 2, "b": 0}, cap=2, replica_cls=DestroyOnDeliver)
    c.issue("a", "b", 1, "t1"); c.deliver(0)
    # safety certificate HOLDS -> this mutant survives a safety-only harness (as it should):
    assert all(r.escrow >= 0 for r in c.replicas.values())      # WF
    assert c.quantity() <= c.cap                                 # Bound
    assert c.total_spent() <= c.cap                              # Safety
    assert not c.conserved()                                     # ...only conservation catches it


def _run_all():
    test_differential_conforms_to_tla(); print("  PASS differential (66==66, invariants hold)")
    run_disciplined(max_examples=1500, steps=40); print("  PASS hostile harness disciplined (1500x40)")
    try:
        run_broken(max_examples=3000); raise SystemExit("teeth check failed to catch broken")
    except AssertionError:
        print("  PASS harness teeth (broken protocol caught)")
    test_bound_can_fail_while_safety_holds_in_broken()
    print("  PASS falsification probe (Bound-fails-while-Safety-holds only in broken)")
    print("OK — Floor E gate checks passed")


if __name__ == "__main__":
    _run_all()
