"""
Floor B tests for the escrow reference implementation.

Runs standalone (`python3 impl/test_escrow.py`) and under pytest. Covers the fault modes
(duplicate charge/delivery, loss, reject, reordering via arbitrary delivery order), a seeded
random-trace invariant check, and a NEGATIVE CONTROL: a dedup-less variant that must trip the
conserved-quantity invariant.
"""
from __future__ import annotations
import random
import sys
from contextlib import contextmanager

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from escrow import EscrowService, InvariantViolation


@contextmanager
def assert_raises(exc):
    try:
        yield
    except exc:
        return
    raise AssertionError(f"expected {exc.__name__} but none was raised")


def test_transfer_moves_budget_conserved():
    s = EscrowService(["a", "b"], cap=3, genesis="a")
    assert s.send_transfer("a", "b", 2, "t1") is True
    assert s.total_escrow() == 1 and s.inflight() == 2 and s.conserved() == 3
    assert s.deliver(0) is True
    assert s.escrow["b"] == 2 and s.inflight() == 0 and s.conserved() == 3


def test_duplicate_delivery_no_double_credit():
    s = EscrowService(["a", "b"], cap=2, genesis="a")
    s.send_transfer("a", "b", 1, "t1")
    assert s.deliver(0) is True                 # first credit
    assert s.deliver(0) is False                # duplicate: idempotent no-op
    assert s.escrow["b"] == 1 and s.conserved() == 2


def test_duplicate_charge_no_double_debit():
    s = EscrowService(["a"], cap=3, genesis="a")
    assert s.charge("a", 2, "op1") is True
    assert s.charge("a", 2, "op1") is True      # duplicate: idempotent, returns True
    assert s.spent["a"] == 2 and s.escrow["a"] == 1
    assert s.per_request_ok()                   # op1 debited exactly once


def test_message_loss_preserves_safety():
    s = EscrowService(["a", "b"], cap=2, genesis="a")
    s.send_transfer("a", "b", 1, "t1")
    assert s.drop(0) is True                     # lost
    assert s.total_spent() <= s.cap and s.conserved() == 2   # unit stays 'in flight' forever
    # the lost unit can never be spent: available budget is now cap - 1
    assert s.total_escrow() + s.total_spent() == 1


def test_reject_when_insufficient_escrow():
    s = EscrowService(["a", "b"], cap=1, genesis="a")
    assert s.charge("b", 1, "op1") is False      # b has no local escrow -> rejected
    assert s.spent["b"] == 0 and s.conserved() == 1


def test_reordering_of_transfers():
    s = EscrowService(["a", "b", "c"], cap=3, genesis="a")
    s.send_transfer("a", "b", 1, "t1")
    s.send_transfer("a", "c", 1, "t2")
    # deliver out of order (t2 before t1)
    assert s.deliver(1) is True and s.deliver(0) is True
    assert s.escrow["b"] == 1 and s.escrow["c"] == 1 and s.escrow["a"] == 1
    assert s.conserved() == 3


def test_random_traces_preserve_invariants():
    """Seeded random op traces: the reference self-checks Conserved & Safety on every step;
    we also assert per-request idempotency holds throughout."""
    replicas = ["a", "b", "c"]
    for seed in range(200):
        rng = random.Random(seed)
        s = EscrowService(replicas, cap=5, genesis="a")
        opids = [f"o{i}" for i in range(4)]
        tids = [f"t{i}" for i in range(4)]
        for _ in range(40):
            op = rng.choice(["charge", "send", "deliver", "drop"])
            if op == "charge":
                s.charge(rng.choice(replicas), rng.randint(0, 3), rng.choice(opids))
            elif op == "send":
                s.send_transfer(rng.choice(replicas), rng.choice(replicas),
                                rng.randint(0, 3), rng.choice(tids))
            elif op == "deliver" and s.net:
                s.deliver(rng.randrange(len(s.net)))
            elif op == "drop" and s.net:
                s.drop(rng.randrange(len(s.net)))
            # reference self-checks Conserved & Safety; assert the separate per-request property
            assert s.per_request_ok(), f"double-charge at seed {seed}"
        assert s.conserved() == 5 and s.total_spent() <= 5


class _NoDedupService(EscrowService):
    """NEGATIVE CONTROL: receive without dedup — duplicate delivery double-credits."""
    def deliver(self, idx: int) -> bool:
        msg = self.net[idx]
        self.escrow[msg.dst] += msg.amount       # BUG: no `if tid in recvd` guard
        self.recvd.add(msg.tid)
        self._check()                            # must raise on the 2nd (duplicate) delivery
        return True


def test_negative_control_no_dedup_is_caught():
    s = _NoDedupService(["a", "b"], cap=2, genesis="a")
    s.send_transfer("a", "b", 1, "t1")
    assert s.deliver(0) is True                  # first credit ok
    with assert_raises(InvariantViolation):      # duplicate delivery breaks Conserved
        s.deliver(0)


def _run_all():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    for t in tests:
        t()
        print(f"  PASS {t.__name__}")
    print(f"OK — {len(tests)} tests passed")


if __name__ == "__main__":
    _run_all()
