"""
Floor D tests for the crash/recovery escrow implementation.

  * PBT (Hypothesis stateful): random schedules of charge / issue / deliver / persist / CRASH
    against the DISCIPLINED config must keep SafetyLe on every step — the executable half of the
    refutation hunt for a crash/partition-induced safety break.
  * Adversarial replays of the three TLC counterexamples as executable negative controls:
      - lazy-debit + sender crash  -> SafetyLe breaks   (SENDER-side fault creates budget)
      - volatile-recvd + crash     -> SafetyLe breaks   (receiver double-credit across a crash)
      - crash under discipline     -> Conserved breaks but Safety holds (destruction is safe)

Runs standalone and under pytest.
"""
from __future__ import annotations
import sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from durable import DurableCluster
from hypothesis import settings, strategies as st
from hypothesis.stateful import RuleBasedStateMachine, rule, invariant, run_state_machine_as_test

REPLICAS = ["a", "b"]
TIDS = [f"t{i}" for i in range(4)]
CAP = 3
# globally-unique transfer identity (id-collision is a separate, already-characterised fault)
TID_IDENTITY = {t: (REPLICAS[i % 2], REPLICAS[(i + 1) % 2], 1 + (i % 2)) for i, t in enumerate(TIDS)}


class CrashMachine(RuleBasedStateMachine):
    """Disciplined config (write-ahead debit + durable recvd). Crashes, checkpoints, and
    arbitrary (re)delivery are all in the schedule."""
    def __init__(self):
        super().__init__()
        self.c = DurableCluster({"a": CAP, "b": 0}, cap=CAP)

    @rule(name=st.sampled_from(REPLICAS), amt=st.integers(0, 2))
    def charge(self, name, amt):
        self.c.charge(name, amt)

    @rule(tid=st.sampled_from(TIDS))
    def issue(self, tid):
        src, dst, amt = TID_IDENTITY[tid]
        self.c.issue(src, dst, amt, tid)

    @rule(data=st.data())
    def deliver(self, data):                          # arbitrary/duplicate/post-crash delivery
        if self.c.sentMsgs:
            self.c.deliver(data.draw(st.integers(0, len(self.c.sentMsgs) - 1)))

    @rule(name=st.sampled_from(REPLICAS))
    def persist(self, name):
        self.c.persist(name)

    @rule(name=st.sampled_from(REPLICAS))
    def crash(self, name):
        self.c.crash(name)

    @invariant()
    def safety(self):
        self.c.check()


CrashMachine.TestCase.settings = settings(max_examples=400, stateful_step_count=50)
TestCrashMachine = CrashMachine.TestCase


# ---- adversarial replays (executable negative controls) ----

def test_lazy_debit_sender_crash_creates_budget():
    """Debit not persisted before send: sender crashes after emitting -> escrow reverts high while
    the transfer is still in flight -> SafetyLe breaks. A SENDER-side crash creates budget, so
    'receiver-side faults are the only safety-critical faults' is FALSE."""
    c = DurableCluster({"a": 2, "b": 0}, cap=2, debit_durable_before_send=False)
    c.issue("a", "b", 1, "t1")            # volatile debit: escrow a 2->1, d_escrow stays 2
    assert c.safety_le()
    c.crash("a")                          # revert: escrow a -> 2, message still in flight
    assert not c.safety_le(), "sender-side crash must create budget (SafetyLe violated)"
    assert c.quantity() == 3              # escrow 2 + inflight 1 > CAP 2


def test_volatile_recvd_double_credit_across_crash():
    """Receiver dedup not durable: credit persisted, recvd lost on crash -> retransmit re-credits
    -> SafetyLe breaks."""
    c = DurableCluster({"a": 2, "b": 0}, cap=2, recvd_durable=False)
    c.issue("a", "b", 1, "t1")
    assert c.deliver(0) is True           # credit b: escrow b=1 (durable), recvd volatile
    c.crash("b")                          # recvd lost; balance kept -> tid re-opens
    assert not c.safety_le(), "lost receiver dedup must let a retransmit over-credit"
    c.deliver(0)                          # retransmit re-credits
    assert c.replicas["b"].escrow == 2 and c.quantity() >= 3


def test_crash_under_discipline_destroys_budget_but_stays_safe():
    """Disciplined config: an un-persisted charge is lost on crash -> Conserved breaks (budget
    destroyed) but Safety holds. Crashes are a DESTRUCTION fault."""
    c = DurableCluster({"a": 2, "b": 0}, cap=2)
    c.charge("a", 1)                      # volatile: spent 1, escrow 1 (d_escrow still 2)
    c.crash("a")                          # revert: spent 0, escrow 2 -> the charge un-happens
    assert c.safety_le() and c.conserved()  # a lone charge reverts cleanly (no external effect)
    # make the loss real: charge (volatile), THEN send (write-ahead persists escrow=0), THEN crash
    c2 = DurableCluster({"a": 2, "b": 0}, cap=2)
    c2.charge("a", 1)                     # escrow 2->1, spent 1 (volatile), d_escrow still 2
    c2.issue("a", "b", 1, "t1")          # escrow 1->0, d_escrow 0 (write-ahead over the charge)
    c2.crash("a")                         # spent -> 0 (lost); escrow -> d_escrow 0
    assert c2.total_spent() <= c2.cap and c2.safety_le()   # Safety holds
    assert not c2.conserved()            # the charged unit is destroyed by the crash


def test_disciplined_survives_hostile_crash_trace():
    c = DurableCluster({"a": 3, "b": 0}, cap=3)
    c.issue("a", "b", 2, "t1"); c.persist("a")
    c.deliver(0); c.crash("b")           # deliver then crash receiver: durable recvd survives
    c.deliver(0)                          # retransmit: idempotent (recvd durable) -> no double credit
    c.check()
    assert c.safety_le() and c.replicas["b"].escrow == 2


def _run_all():
    run_state_machine_as_test(CrashMachine,
                              settings=settings(max_examples=400, stateful_step_count=50))
    print("  PASS property-based crash machine (disciplined config)")
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn(); print(f"  PASS {name}")
    print("OK — Floor D durable/crash tests passed")


if __name__ == "__main__":
    _run_all()
