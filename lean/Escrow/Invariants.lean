/-
  Escrow/Invariants.lean — the crash-free protocol conserves authority, so the certificate
  `WF ∧ InFlightNonneg ∧ Bound` is inductive.

  Core fact: every transition preserves `A = Σspent + Σescrow + InFlight` exactly (A_preserved).
  Since genesis has `A = CAP`, `Bound (A ≤ CAP)` is preserved; `WF`/`InFlightNonneg` are immediate
  over `Nat`. `DestOk` (destinations are real replicas) is a separate structural invariant needed
  for the receive case.
-/
import Escrow.Protocol
namespace Escrow

variable {R T : Type} [DecidableEq R] [DecidableEq T]

/-- An unsent transfer contributes 0 to InFlight. -/
theorem contrib_unsent {s : State R T} {t : T} (h : s.phase t = Phase.unsent) :
    contrib s t = 0 := by simp [contrib, h]

/-- An in-flight transfer contributes its amount. -/
theorem contrib_inflight {s : State R T} {t : T} (h : s.phase t = Phase.inflight) :
    contrib s t = s.amt t := by simp [contrib, h]

/-- contrib after a send is the old contrib updated to `a` at `t`. -/
theorem contrib_send (s : State R T) (i j : R) (t : T) (a : Nat) :
    contrib { s with escrow := upd s.escrow i (s.escrow i - a),
                     phase := upd s.phase t Phase.inflight, amt := upd s.amt t a,
                     dest := upd s.dest t j } = upd (contrib s) t a := by
  funext t'
  by_cases h : t' = t
  · subst h; simp [contrib, upd]
  · simp [contrib, upd, h]

/-- contrib after a receive is the old contrib set to `0` at `t`. -/
theorem contrib_recv (s : State R T) (t : T) :
    contrib { s with escrow := upd s.escrow (s.dest t) (s.escrow (s.dest t) + s.amt t),
                     phase := upd s.phase t Phase.received } = upd (contrib s) t 0 := by
  funext t'
  by_cases h : t' = t
  · subst h; simp [contrib, upd]
  · simp [contrib, upd, h]

/-- InFlight rises by `a` on a send of a previously-unsent transfer. -/
theorem inflight_send {ts : List T} (s : State R T) (i j : R) (t : T) (a : Nat)
    (hun : s.phase t = Phase.unsent) (ht : t ∈ ts) (htn : ts.Nodup) :
    inflight ts { s with escrow := upd s.escrow i (s.escrow i - a),
                         phase := upd s.phase t Phase.inflight, amt := upd s.amt t a,
                         dest := upd s.dest t j } = inflight ts s + a := by
  simp only [inflight]
  rw [contrib_send]
  have hz : contrib s t = 0 := contrib_unsent hun
  have key := sumOver_upd_add (contrib s) a ht htn
  rw [hz] at key
  simpa using key

/-- InFlight falls by `amt t` on a receive of an in-flight transfer. -/
theorem inflight_recv {ts : List T} (s : State R T) (t : T)
    (hin : s.phase t = Phase.inflight) (ht : t ∈ ts) (htn : ts.Nodup) :
    inflight ts { s with escrow := upd s.escrow (s.dest t) (s.escrow (s.dest t) + s.amt t),
                         phase := upd s.phase t Phase.received } + s.amt t = inflight ts s := by
  simp only [inflight]
  rw [contrib_recv]
  have hc : contrib s t = s.amt t := contrib_inflight hin
  have key := sumOver_upd_sub (contrib s) (s.amt t) ht htn (Nat.le_of_eq hc.symm)
  rw [hc] at key
  simpa using key

/-- **Conservation**: every crash-free transition preserves total authority `A`. -/
theorem A_preserved {rs : List R} {ts : List T} {s s' : State R T}
    (hrn : rs.Nodup) (htn : ts.Nodup) (hdo : DestOk rs s) (h : Step rs ts s s') :
    A rs ts s' = A rs ts s := by
  cases h with
  | charge r a hr hle =>
    have he := sumOver_upd_sub s.escrow a hr hrn hle
    have hsp := sumOver_upd_add s.spent a hr hrn
    have hif : inflight ts { s with escrow := upd s.escrow r (s.escrow r - a),
                                    spent := upd s.spent r (s.spent r + a) } = inflight ts s := rfl
    simp only [A, sumEscrow, sumSpent] at *
    omega
  | send i j t a hi hj ht hun hle =>
    have he := sumOver_upd_sub s.escrow a hi hrn hle
    have hif := inflight_send s i j t a hun ht htn
    have hsp : sumSpent rs { s with escrow := upd s.escrow i (s.escrow i - a),
                                    phase := upd s.phase t Phase.inflight, amt := upd s.amt t a,
                                    dest := upd s.dest t j } = sumSpent rs s := rfl
    simp only [A, sumEscrow, sumSpent] at *
    omega
  | recv t ht hin =>
    have hd : s.dest t ∈ rs := hdo t
    have he := sumOver_upd_add s.escrow (s.amt t) hd hrn
    have hif := inflight_recv s t hin ht htn
    have hsp : sumSpent rs { s with escrow := upd s.escrow (s.dest t) (s.escrow (s.dest t) + s.amt t),
                                    phase := upd s.phase t Phase.received } = sumSpent rs s := rfl
    simp only [A, sumEscrow, sumSpent] at *
    omega
  | drop => rfl
  | noop => rfl

/-- `DestOk` is preserved: sends only ever point at replicas in `rs`. -/
theorem destOk_preserved {rs : List R} {ts : List T} {s s' : State R T}
    (hdo : DestOk rs s) (h : Step rs ts s s') : DestOk rs s' := by
  cases h with
  | charge r a hr hle => exact hdo
  | send i j t a hi hj ht hun hle =>
    intro t'; by_cases h : t' = t
    · subst h; simpa [upd] using hj
    · simpa [upd, h] using hdo t'
  | recv t ht hin => exact hdo
  | drop => exact hdo
  | noop => exact hdo

/-- WF is immediate over `Nat`. -/
theorem wf_all (rs : List R) (s : State R T) : WF rs s := by intro r _; exact Nat.zero_le _
/-- InFlightNonneg is immediate over `Nat`. -/
theorem inflightNonneg_all (ts : List T) (s : State R T) : InFlightNonneg ts s := Nat.zero_le _

/-- Genesis establishes `DestOk`, `A = CAP` (hence `Bound`), for any `CAP` incl. 0. -/
theorem genesis_destOk {rs : List R} {g : R} (cap : Nat) (hg : g ∈ rs) :
    DestOk rs (genesis (T := T) g cap) := by intro _; exact hg

theorem genesis_A {rs : List R} {ts : List T} {g : R} (cap : Nat)
    (hg : g ∈ rs) (hrn : rs.Nodup) : A rs ts (genesis (T := T) g cap) = cap := by
  have hesc : sumEscrow rs (genesis (T := T) g cap) = cap := by
    show sumOver rs (fun r => if r = g then cap else 0) = cap
    exact sumOver_single cap hg hrn
  have hsp : sumSpent rs (genesis (T := T) g cap) = 0 := by
    show sumOver rs (fun _ => 0) = 0; exact sumOver_zero rs
  have hif : inflight ts (genesis (T := T) g cap) = 0 := by
    show sumOver ts (contrib (genesis (T := T) g cap)) = 0
    have : contrib (genesis (T := T) g cap) = fun _ => 0 := by
      funext t; simp [contrib, genesis]
    rw [this]; exact sumOver_zero ts
  simp only [A]; omega

end Escrow
