"""
Floor E — hostile fault-injection harness.

A stateful Hypothesis machine over the crash/recovery cluster (impl/durable.py, disciplined
config: write-ahead debit + durable receiver dedup) that COMPOSES every fault:

  duplicated delivery · duplicated/retried send · arbitrary reorder · retry storms · message
  loss · delayed delivery · crash-before-persist · crash-after-persist · repeated crash/recovery ·
  simultaneous crashes · random scheduling · random replica choice.

Config is drawn per execution (replica count, CAP, transfer amounts), so a single run varies all
of them and shrinks any counterexample. The frozen certificate is checked after EVERY step:

  WF     : ∀r escrow[r] ≥ 0
  Bound  : A = Σspent + Σescrow + InFlight ≤ CAP
  Safety : Σspent ≤ CAP

A failure is raised with its CLASSIFICATION label so a shrunk counterexample names its category.
The same machine can be pointed at a BROKEN config (recvd_durable / debit_durable off) to prove
the harness has teeth (see run_broken()).
"""
from __future__ import annotations
import sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from durable import DurableCluster
from hypothesis import settings, strategies as st, HealthCheck
from hypothesis.stateful import RuleBasedStateMachine, rule, initialize, invariant, run_state_machine_as_test


class CertificateViolation(AssertionError):
    pass


class _Base(RuleBasedStateMachine):
    # subclasses set these
    DDBS = True
    RD = True

    def __init__(self):
        super().__init__()
        self.c = None
        self.names = []
        self.cap = 0
        self._tid = 0
        self._maxamt = 1
        self.transfers = {}   # tid -> (src, dst, amount)

    @initialize(cap=st.integers(min_value=1, max_value=6),
                nrep=st.integers(min_value=2, max_value=4),
                maxamt=st.integers(min_value=1, max_value=3))
    def setup(self, cap, nrep, maxamt):
        self.names = [f"r{i}" for i in range(nrep)]
        self.cap = cap
        self._maxamt = maxamt
        alloc = {n: (cap if i == 0 else 0) for i, n in enumerate(self.names)}
        self.c = DurableCluster(alloc, cap=cap,
                                debit_durable_before_send=self.DDBS, recvd_durable=self.RD)

    # ---- fault-injecting rules ----
    @rule(data=st.data())
    def charge(self, data):
        if not self.names: return
        r = data.draw(st.sampled_from(self.names))
        a = data.draw(st.integers(1, self._maxamt))
        self.c.charge(r, a)

    @rule(data=st.data())
    def issue_fresh(self, data):                       # new transfer (unique id)
        if not self.names: return
        src = data.draw(st.sampled_from(self.names))
        dst = data.draw(st.sampled_from(self.names))
        a = data.draw(st.integers(1, self._maxamt))
        tid = f"t{self._tid}"; self._tid += 1
        if self.c.issue(src, dst, a, tid):
            self.transfers[tid] = (src, dst, a)

    @rule(data=st.data())
    def issue_retry(self, data):                       # duplicated/retried send (idempotent)
        if not self.transfers: return
        tid = data.draw(st.sampled_from(sorted(self.transfers)))
        src, dst, a = self.transfers[tid]
        self.c.issue(src, dst, a, tid)                 # disciplined sender -> no re-debit

    @rule(data=st.data())
    def deliver(self, data):                           # arbitrary reorder / delayed delivery
        if not self.c.sentMsgs: return
        self.c.deliver(data.draw(st.integers(0, len(self.c.sentMsgs) - 1)))

    @rule(data=st.data())
    def deliver_storm(self, data):                     # duplicated delivery / retry storm
        n = len(self.c.sentMsgs)
        if n == 0: return
        for _ in range(data.draw(st.integers(2, 6))):
            self.c.deliver(data.draw(st.integers(0, n - 1)))

    @rule(data=st.data())
    def drop(self, data):                              # message loss
        if not self.c.sentMsgs: return
        self.c.drop(data.draw(st.integers(0, len(self.c.sentMsgs) - 1)))

    @rule(data=st.data())
    def persist(self, data):
        if not self.names: return
        self.c.persist(data.draw(st.sampled_from(self.names)))

    @rule(data=st.data())
    def crash(self, data):                             # crash before/after persist (interleaved)
        if not self.names: return
        self.c.crash(data.draw(st.sampled_from(self.names)))

    @rule(data=st.data())
    def crash_repeat(self, data):                      # repeated crash/recovery of one replica
        if not self.names: return
        r = data.draw(st.sampled_from(self.names))
        for _ in range(data.draw(st.integers(2, 4))):
            self.c.crash(r)

    @rule()
    def crash_all(self):                               # simultaneous crashes
        for n in self.names:
            self.c.crash(n)

    # ---- frozen certificate, classified ----
    @invariant()
    def certificate(self):
        if self.c is None: return
        wf = all(r.escrow >= 0 for r in self.c.replicas.values())
        A = self.c.quantity()
        spent = self.c.total_spent()
        if not wf:
            raise CertificateViolation(f"WF violated: escrow<0 (A={A}, spent={spent}, cap={self.cap})")
        if A > self.cap:
            raise CertificateViolation(f"Bound violated: A={A} > CAP={self.cap}")
        if spent > self.cap:
            raise CertificateViolation(f"Safety violated: spent={spent} > CAP={self.cap}")


class HostileDisciplined(_Base):
    """The real, disciplined protocol. Expected: certificate holds under all composed faults."""
    DDBS = True
    RD = True


class HostileVolatileRecvd(_Base):
    """Negative control: receiver dedup NOT durable. Harness must FIND a Bound/Safety break."""
    DDBS = True
    RD = False


_SETTINGS = settings(max_examples=10000, stateful_step_count=40, deadline=None,
                     suppress_health_check=[HealthCheck.too_slow, HealthCheck.filter_too_much])


def run_disciplined(max_examples=10000, steps=40):
    s = settings(max_examples=max_examples, stateful_step_count=steps, deadline=None,
                 suppress_health_check=[HealthCheck.too_slow, HealthCheck.filter_too_much])
    run_state_machine_as_test(HostileDisciplined, settings=s)


def run_broken(max_examples=2000, steps=40):
    s = settings(max_examples=max_examples, stateful_step_count=steps, deadline=None,
                 suppress_health_check=[HealthCheck.too_slow, HealthCheck.filter_too_much])
    run_state_machine_as_test(HostileVolatileRecvd, settings=s)


if __name__ == "__main__":
    import time
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 10000
    print(f"[1] hostile harness on DISCIPLINED protocol: {n} executions x 40 steps ...")
    t = None
    try:
        from time import perf_counter
        t0 = perf_counter()
        run_disciplined(max_examples=n)
        print(f"    certificate held across all {n} executions in {perf_counter()-t0:.1f}s")
    except CertificateViolation as e:
        print(f"    *** CERTIFICATE VIOLATED (theory-breaking counterexample): {e}")
        raise
    print("[2] teeth check: same harness on BROKEN (volatile-recvd) protocol, expect a violation ...")
    try:
        run_broken(max_examples=3000)
        print("    *** HARNESS HAS NO TEETH: broken protocol survived (this would be a problem)")
        raise SystemExit(1)
    except AssertionError as e:
        print(f"    harness caught the broken protocol as expected: {str(e)[:90]}")
    print("OK — Floor E hostile harness: disciplined holds, broken caught")
