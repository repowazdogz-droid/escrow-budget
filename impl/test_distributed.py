"""
Floor C tests for the distributed escrow implementation.

  * Property-based / model-based testing (Hypothesis RuleBasedStateMachine): random adversarial
    schedules of charge / issue / deliver / duplicate-deliver / drop against the CORRECT config
    must preserve SafetyLe and Conserved on every step.
  * Adversarial replays of the TLC counterexamples, as executable negative controls:
      - receiver-side duplicate CREATES budget    -> SafetyLe breaks   (receiver idemp NEEDED)
      - sender-side retry DESTROYS budget          -> Conserved breaks but SafetyLe HOLDS
        (sender idemp NOT needed for the cap — the Floor C separation).

Runs standalone (`python3 impl/test_distributed.py`) and under pytest.
"""
from __future__ import annotations
import sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from distributed import Cluster
from hypothesis import settings, strategies as st
from hypothesis.stateful import RuleBasedStateMachine, rule, invariant, run_state_machine_as_test

REPLICAS = ["a", "b", "c"]
OPIDS = [f"o{i}" for i in range(6)]
TIDS = [f"t{i}" for i in range(6)]
CAP = 4

# A transfer id GLOBALLY identifies one transfer: fixed (src, dst, amount). The protocol assumes
# unique ids, so the generator binds each tid to one identity; a re-issue of a tid is then a
# genuine retry of the SAME transfer (not an id collision). Id collisions are tested separately
# in test_id_collision_breaks_conservation_not_safety.
TID_IDENTITY = {t: (REPLICAS[i % 3], REPLICAS[(i + 1) % 3], 1 + (i % 3))
                for i, t in enumerate(TIDS)}


class EscrowMachine(RuleBasedStateMachine):
    """Correct config (both idempotencies ON). The network may reorder, duplicate, and drop."""
    def __init__(self):
        super().__init__()
        self.c = Cluster({"a": CAP, "b": 0, "c": 0}, cap=CAP)

    @rule(name=st.sampled_from(REPLICAS), amt=st.integers(0, 3), opid=st.sampled_from(OPIDS))
    def charge(self, name, amt, opid):
        self.c.charge(name, amt, opid)

    @rule(tid=st.sampled_from(TIDS))
    def issue(self, tid):
        src, dst, amt = TID_IDENTITY[tid]     # globally-unique transfer identity
        self.c.issue(src, dst, amt, tid)

    @rule(data=st.data())
    def deliver(self, data):
        if self.c.net:
            self.c.deliver(data.draw(st.integers(0, len(self.c.net) - 1)))

    @rule(data=st.data())
    def duplicate_deliver(self, data):
        # net retains delivered messages, so delivering again models duplication/reordering
        if self.c.net:
            self.c.deliver(data.draw(st.integers(0, len(self.c.net) - 1)))

    @rule(data=st.data())
    def drop(self, data):
        if self.c.net:
            self.c.drop(data.draw(st.integers(0, len(self.c.net) - 1)))

    @invariant()
    def invariants_hold(self):
        self.c.check()                       # SafetyLe AND Conserved (correct config)
        assert self.c.per_request_ok()


EscrowMachine.TestCase.settings = settings(max_examples=300, stateful_step_count=40)
TestEscrowMachine = EscrowMachine.TestCase   # pytest picks this up


# ---- adversarial replays (executable negative controls mirroring the TLC counterexamples) ----

def test_receiver_dup_creates_budget_breaks_safety():
    """Receiver idempotency OFF: the same message delivered twice creates budget -> SafetyLe
    breaks. This is why receiver-side transfer idempotency is NECESSARY for the cap."""
    c = Cluster({"a": 2, "b": 0}, cap=2, receiver_idempotent=False)
    c.issue("a", "b", 1, "t1")
    assert c.deliver(0) is True and c.safety_le()      # first credit: fine
    c.deliver(0)                                        # duplicate delivery: re-credits
    assert not c.safety_le(), "receiver-dup must create budget (SafetyLe violated)"
    assert c.replicas["b"].escrow == 2 and c.quantity() == 3  # b credited twice; 3 > CAP 2


def test_sender_dup_destroys_budget_safety_holds_conserved_breaks():
    """Sender idempotency OFF: a re-issued transfer re-debits, DESTROYING budget. Conserved
    breaks (< CAP) but SafetyLe HOLDS. This is the Floor C separation: sender-side transfer
    idempotency is NOT needed for the cap theorem."""
    c = Cluster({"a": 2, "b": 0}, cap=2, sender_idempotent=False)
    c.issue("a", "b", 1, "t1")                          # debit 1: escrow a=1, inflight=1
    c.issue("a", "b", 1, "t1")                          # NON-idempotent retry: re-debit -> a=0
    assert c.safety_le(), "sender-dup must remain safe (only destroys budget)"
    assert not c.conserved(), "sender-dup must break the exact conservation equality"
    assert c.total_spent() <= c.cap and c.quantity() == 1  # 1 unit lost, still <= CAP


def test_correct_config_survives_hostile_trace():
    """Hand-crafted hostile schedule (reorder + duplicate + drop + idempotent retry) under the
    correct config keeps BOTH SafetyLe and Conserved on every step."""
    c = Cluster({"a": 3, "b": 0, "c": 0}, cap=3)
    c.issue("a", "b", 2, "t1")
    c.issue("a", "c", 1, "t2")
    c.issue("a", "b", 2, "t1")            # idempotent retry: no re-debit
    c.check()
    c.deliver(1); c.check()              # deliver t2 first (reorder)
    c.deliver(1)                          # duplicate delivery of t2: idempotent no-op
    c.check()
    c.deliver(0); c.check()              # deliver t1
    assert c.conserved() and c.replicas["b"].escrow == 2 and c.replicas["c"].escrow == 1


def test_id_collision_breaks_conservation_not_safety():
    """Transfer-id UNIQUENESS is required for Conserved, NOT for Safety. Two distinct transfers
    reusing one id 't1' (from a and from b) each debit, but the receiver dedups on the id and
    credits once -> budget is DESTROYED, not created. Conserved breaks; SafetyLe holds. Same
    shape as the sender-dup finding: extra debits only shrink available budget. (Tested-only
    evidence; the model-checked findings are the sender/receiver-idempotency ones.)"""
    c = Cluster({"a": 1, "b": 1}, cap=2)
    c.issue("a", "b", 1, "t1")            # transfer #1 debits a
    c.issue("b", "a", 1, "t1")            # DIFFERENT transfer, colliding id -> debits b too
    # both debited (a=0, b=0); nominal amount for t1 fixed at first issue
    assert c.safety_le(), "id collision must stay safe (extra debit only destroys budget)"
    assert not c.conserved(), "id collision must break exact conservation"
    assert c.total_spent() <= c.cap and c.quantity() < c.cap


def test_loss_preserves_safety_and_conservation():
    c = Cluster({"a": 2, "b": 0}, cap=2)
    c.issue("a", "b", 1, "t1")
    c.drop(0)                             # lost forever
    assert c.conserved() and c.safety_le()          # lost unit stays 'in flight'
    assert c.total_escrow() + c.total_spent() == 1  # usable budget dropped to 1


def _run_all():
    run_state_machine_as_test(EscrowMachine,
                              settings=settings(max_examples=300, stateful_step_count=40))
    print("  PASS property-based stateful machine (correct config)")
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn(); print(f"  PASS {name}")
    print("OK — Floor C distributed tests passed")


if __name__ == "__main__":
    _run_all()
