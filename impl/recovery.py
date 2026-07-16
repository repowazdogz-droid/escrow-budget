"""
Theory-checkpoint executable: separate SAFETY, NON-CREATION, CONSERVATION and WELL-FORMEDNESS,
and compare the signed vs floored authority quantities on the same states.

Authority in circulation is the SIGNED linear quantity  A = Σspent + Σescrow.  Lost authority
moves to `stranded` (out of A). Reclaim moves it back (A rises). Overdraft is allowed here ONLY
to study it: a charge past escrow drives escrow negative — a WELL-FORMEDNESS violation, distinct
from authority creation.

Quantities exposed:
  signed_A   = Σspent + Σescrow                    (linear; clean for conservation/non-creation)
  floored_A  = Σspent + Σ max(escrow,0)            (the A⁺ of the checkpoint; single scalar)
  wf         = ∀r escrow[r] ≥ 0                     (solvency / no-overdraft)
  safety     = Σspent ≤ CAP
The point (see tests): `signed_A ≤ CAP` alone does NOT imply safety (overdraft breaks it); you
need `signed_A ≤ CAP ∧ wf`.  `floored_A ≤ CAP` alone DOES imply safety but is non-linear.
"""
from __future__ import annotations


class RecoveryLedger:
    def __init__(self, replicas: dict[str, int], cap: int):
        self.cap = cap
        self.escrow = dict(replicas)
        self.spent = {r: 0 for r in replicas}
        self.stranded = 0

    def total_escrow(self): return sum(self.escrow.values())
    def total_spent(self):  return sum(self.spent.values())
    def signed_A(self):     return self.total_spent() + self.total_escrow()
    def floored_A(self):    return self.total_spent() + sum(max(e, 0) for e in self.escrow.values())
    def wf(self):           return all(e >= 0 for e in self.escrow.values())
    def safety(self):       return self.total_spent() <= self.cap
    def bound_signed(self): return self.signed_A() <= self.cap
    def bound_floored(self):return self.floored_A() <= self.cap

    def charge(self, r, a, *, allow_overspend=False):     # conserving in signed_A (escrow->spent)
        if allow_overspend or a <= self.escrow[r]:
            self.escrow[r] -= a; self.spent[r] += a
            return True
        return False

    def lose(self, r, a):                                  # destroying: escrow -> stranded (A down)
        if a <= self.escrow[r]:
            self.escrow[r] -= a; self.stranded += a
            return True
        return False

    def reclaim(self, r, a, *, safe=True):                # restoring: stranded -> escrow (A up)
        if safe and a > self.stranded:
            return False                                  # guard: only what was stranded
        self.escrow[r] += a
        if safe:
            self.stranded -= a
        return True
