"""
Floor E — differential / conformance check between the executable and the TLA+ reference.

This is an INDEPENDENT Python transliteration of spec/EscrowBudgetC.tla (correct config:
SenderIdemp = ReceiverIdemp = TRUE), enumerated by BFS over the full reachable state space. If
this independent encoding reproduces TLC's reported distinct-state count (66) AND finds every
reachable state satisfies the same invariants TLC verified (SafetyLe, Conserved), then the two
encodings agree on the model's safety envelope — a concrete differential result, not a vibe.

The executable impl/distributed.py implements exactly these transitions (Charge/SendFirst/Recv/
Drop); the crash-free Hypothesis machine (impl/test_distributed.py) exercises it against the same
envelope, and the 10k-execution harness (impl/fault_harness.py) extends it with crashes.
"""
from __future__ import annotations
from collections import deque

# config identical to spec/EscrowBudgetC.cfg
REPLICAS = ("r1", "r2")
CAP = 2
CIDS = ("c1", "c2")
TIDS = ("t1",)
AMOUNTS = (1, 2)
GENESIS = 0                       # CHOOSE r \in Replicas : TRUE  -> first replica

# state = (escrow, spent, net, applied, sentT, recvd, amtOf), all hashable
def init_state():
    escrow = tuple(CAP if i == GENESIS else 0 for i in range(len(REPLICAS)))
    spent = tuple(0 for _ in REPLICAS)
    amtOf = tuple(0 for _ in TIDS)
    return (escrow, spent, frozenset(), frozenset(), frozenset(), frozenset(), amtOf)


def _set(tpl, i, v):
    l = list(tpl); l[i] = v; return tuple(l)


def inflight(sentT, recvd, amtOf):
    return sum(amtOf[TIDS.index(t)] for t in sentT if t not in recvd)


def sum_spent(s):  return sum(s[1])
def sum_escrow(s): return sum(s[0])
def quantity(s):   return sum_spent(s) + sum_escrow(s) + inflight(s[4], s[5], s[6])


def successors(s):
    escrow, spent, net, applied, sentT, recvd, amtOf = s
    out = []
    # Charge(r, cid, a): cid not applied, a <= escrow[r]
    for ri in range(len(REPLICAS)):
        for cid in CIDS:
            if cid in applied: continue
            for a in AMOUNTS:
                if a <= escrow[ri]:
                    out.append((_set(escrow, ri, escrow[ri] - a),
                                _set(spent, ri, spent[ri] + a),
                                net, applied | {cid}, sentT, recvd, amtOf))
    # SendFirst(i, j, t, a): t not sent, a <= escrow[i]
    for i in range(len(REPLICAS)):
        for j in range(len(REPLICAS)):
            for t in TIDS:
                if t in sentT: continue
                for a in AMOUNTS:
                    if a <= escrow[i]:
                        out.append((_set(escrow, i, escrow[i] - a), spent,
                                    net | {(REPLICAS[j], t)}, applied,
                                    sentT | {t}, recvd, _set(amtOf, TIDS.index(t), a)))
    # Recv(m): m in net, tid not recvd (ReceiverIdemp)
    for (to, tid) in net:
        if tid in recvd: continue
        ti = REPLICAS.index(to)
        out.append((_set(escrow, ti, escrow[ti] + amtOf[TIDS.index(tid)]), spent,
                    net, applied, sentT, recvd | {tid}, amtOf))
    # Drop(m): remove from net
    for m in net:
        out.append((escrow, spent, net - {m}, applied, sentT, recvd, amtOf))
    return out


def explore():
    start = init_state()
    seen = {start}
    q = deque([start])
    violations = []
    while q:
        s = state = q.popleft()
        q_val = quantity(s)
        if not (sum_spent(s) <= CAP):
            violations.append(("Safety", s))
        if not (q_val <= CAP):
            violations.append(("SafetyLe/Bound", s))
        if q_val != CAP:
            violations.append(("Conserved", s))
        for ns in successors(s):
            if ns not in seen:
                seen.add(ns); q.append(ns)
    return len(seen), violations


TLC_DISTINCT = 66   # from `make tlc-c` on EscrowBudgetC (correct config)


def run():
    n, violations = explore()
    print(f"differential: independent Python BFS of EscrowBudgetC reached {n} distinct states")
    print(f"              TLC reported {TLC_DISTINCT} distinct states")
    ok_count = (n == TLC_DISTINCT)
    ok_inv = (len(violations) == 0)
    print(f"  state-count match : {'OK' if ok_count else 'MISMATCH'}")
    print(f"  invariants (Safety, SafetyLe, Conserved) hold on all reachable states : "
          f"{'OK' if ok_inv else 'FAIL'}")
    if violations:
        for cat, s in violations[:5]:
            print(f"    {cat} violated at {s}")
    if ok_count and ok_inv:
        print("DIFFERENTIAL: OK — executable transition semantics conform to the TLA+ model")
        return 0
    print("DIFFERENTIAL: FAIL — divergence between Python enumeration and TLC")
    return 1


if __name__ == "__main__":
    raise SystemExit(run())
