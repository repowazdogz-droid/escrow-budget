"""
Theory-checkpoint tests: keep Safety, Non-creation, Conservation and Well-formedness apart.

  * PBT (safe reclaim): the SAFETY CERTIFICATE `wf ∧ signed_A ≤ CAP` holds on every step, even as
    authority is lost and reclaimed — while non-creation and conservation are NOT asserted (they
    legitimately fail).
  * Explicit distinctions:
      - safe reclaim: signed_A INCREASES but stays ≤ CAP, safety holds  (counterexample to D)
      - unsafe reclaim: signed_A > CAP -> safety lost                    (creation beyond CAP)
      - overdraft: signed_A unchanged (conserving!) but wf fails and safety lost
                   -> signed_A ≤ CAP alone is NOT a safety cert; floored_A catches it
      - loss: signed_A decreases -> conservation lost, safety holds
"""
from __future__ import annotations
import sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from recovery import RecoveryLedger
from hypothesis import settings, strategies as st
from hypothesis.stateful import RuleBasedStateMachine, rule, invariant, run_state_machine_as_test

CAP = 3
REPLICAS = ["a", "b"]


class SafeRecoveryMachine(RuleBasedStateMachine):
    """Lossy + safe-reclaim ledger. The safety certificate must hold on every step; monotonicity
    and conservation are deliberately NOT invariants (they legitimately fail here)."""
    def __init__(self):
        super().__init__()
        self.l = RecoveryLedger({"a": CAP, "b": 0}, cap=CAP)

    @rule(r=st.sampled_from(REPLICAS), a=st.integers(1, 2))
    def charge(self, r, a):
        self.l.charge(r, a)                    # guarded (no overspend) -> wf preserved

    @rule(r=st.sampled_from(REPLICAS), a=st.integers(1, 2))
    def lose(self, r, a):
        self.l.lose(r, a)

    @rule(r=st.sampled_from(REPLICAS), a=st.integers(1, 2))
    def reclaim(self, r, a):
        self.l.reclaim(r, a, safe=True)

    @invariant()
    def safety_certificate(self):
        assert self.l.wf(), "well-formedness (no overdraft) must hold"
        assert self.l.bound_signed(), f"Bound broken: signed_A {self.l.signed_A()} > {CAP}"
        assert self.l.safety(), "Safety must hold"


SafeRecoveryMachine.TestCase.settings = settings(max_examples=400, stateful_step_count=50)
TestSafeRecoveryMachine = SafeRecoveryMachine.TestCase


def test_safe_reclaim_A_increases_within_headroom():
    """Counterexample to 'every A increase is unsafe': lose then reclaim -> signed_A goes
    3 -> 2 -> 3, an INCREASE that stays ≤ CAP. Safety holds; non-creation is violated."""
    l = RecoveryLedger({"a": 3, "b": 0}, cap=3)
    assert l.signed_A() == 3
    l.lose("a", 1);   assert l.signed_A() == 2                 # authority destroyed
    before = l.signed_A()
    l.reclaim("a", 1, safe=True)
    assert l.signed_A() == 3 and l.signed_A() > before        # authority RESTORED (A increased)
    assert l.bound_signed() and l.safety()                    # ...yet still safe


def test_unsafe_reclaim_creates_beyond_cap():
    l = RecoveryLedger({"a": 3, "b": 0}, cap=3)
    l.reclaim("a", 2, safe=False)                             # invents authority
    assert not l.bound_signed()                               # signed_A = 5 > CAP
    l.charge("a", 2); l.charge("a", 2)                        # spend the excess
    assert not l.safety()                                     # Σspent = 4 > CAP 3


def test_overdraft_conserves_signedA_but_breaks_wf_and_safety():
    """The decisive distinction: an overdraft charge is CONSERVING in signed_A (ΔsignedA = 0) and
    keeps signed_A ≤ CAP, yet Safety FAILS. So `signed_A ≤ CAP` is NOT a safety certificate on its
    own — you need `wf` too. The floored quantity A⁺ does catch it (that is its whole purpose)."""
    l = RecoveryLedger({"a": 2, "b": 0}, cap=2)
    l.charge("a", 2)                                          # escrow a: 2->0, spent 2 (fine)
    l.charge("a", 2, allow_overspend=True)                    # escrow a: 0->-2, spent 4 (overdraft)
    assert l.signed_A() == 2 and l.bound_signed()            # signed_A still = CAP (conserving!)
    assert not l.wf()                                         # ...but escrow < 0 (overdraft)
    assert not l.safety()                                    # ...and Σspent 4 > CAP 2
    assert l.floored_A() == 4 and not l.bound_floored()      # floored A⁺ = 4 > CAP -> caught


def test_loss_breaks_conservation_but_not_safety():
    l = RecoveryLedger({"a": 3, "b": 0}, cap=3)
    before = l.signed_A()
    l.lose("a", 2)
    assert l.signed_A() < before                             # conservation lost
    assert l.safety() and l.bound_signed() and l.wf()        # safety intact


def _run_all():
    run_state_machine_as_test(SafeRecoveryMachine,
                              settings=settings(max_examples=400, stateful_step_count=50))
    print("  PASS property-based safe-recovery machine (safety cert holds; non-creation not asserted)")
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn(); print(f"  PASS {name}")
    print("OK — theory-checkpoint recovery tests passed")


if __name__ == "__main__":
    _run_all()
