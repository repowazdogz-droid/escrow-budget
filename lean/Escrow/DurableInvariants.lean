/-
  Escrow/DurableInvariants.lean — the joint invariant `Jinv` is inductive.

  Methodology (as required): we attempt the WEAKEST plausible invariant —
  `Bound cur ∧ Bound dur ∧ DestOk cur ∧ DestOk dur` — and every preservation obligation closes,
  so no consistency clause (phase-lockstep, escrow≤durable, …) is needed: the discipline lives in
  the TRANSITIONS (write-ahead debit and durable dedup are the durable updates in `send`/`recv`,
  and their explicit durable guards). Removing either durable update breaks `Bound dur` — see
  Escrow/DurableNegative.lean. Each component obligation reuses the crash-free `A_preserved` /
  `destOk_preserved` on the underlying Floor-F1 step.
-/
import Escrow.DurableProtocol
namespace Escrow

variable {R T : Type} [DecidableEq R] [DecidableEq T]

/-- Conservation transports the bound: if a step preserves `A`, it preserves `Bound`. -/
theorem Bound_of_A_eq {rs : List R} {ts : List T} {cap : Nat} {s s' : State R T}
    (h : A rs ts s' = A rs ts s) (hb : Bound cap rs ts s) : Bound cap rs ts s' := by
  simp only [Bound] at *; omega

/-- Genesis establishes the joint invariant (current and durable both = the F1 genesis). -/
theorem genesis_Jinv {rs : List R} {ts : List T} {g : R} {cap : Nat}
    (hg : g ∈ rs) (hrn : rs.Nodup) : Jinv cap rs ts (Dgenesis (T := T) g cap) := by
  have hA : A rs ts (genesis (T := T) g cap) = cap := genesis_A cap hg hrn
  have hb : Bound cap rs ts (genesis (T := T) g cap) := by simp only [Bound]; omega
  exact ⟨hb, hb, genesis_destOk cap hg, genesis_destOk cap hg⟩

/-- Every disciplined transition preserves the joint invariant. -/
theorem Jinv_preserved {rs : List R} {ts : List T} {cap : Nat} {d d' : DState R T}
    (hrn : rs.Nodup) (htn : ts.Nodup) (h : DStep rs ts d d') (hj : Jinv cap rs ts d) :
    Jinv cap rs ts d' := by
  obtain ⟨hbc, hbd, hdc, hdd⟩ := hj
  cases h with
  | charge r a hr hle =>
    have st : Step rs ts d.cur
        { d.cur with escrow := upd d.cur.escrow r (d.cur.escrow r - a),
                     spent := upd d.cur.spent r (d.cur.spent r + a) } := Step.charge d.cur r a hr hle
    have hA := A_preserved hrn htn hdc st
    exact ⟨Bound_of_A_eq hA hbc, hbd, destOk_preserved hdc st, hdd⟩
  | send i j t a hi hj ht hcun hdun hcle hdle =>
    have stc : Step rs ts d.cur
        { d.cur with escrow := upd d.cur.escrow i (d.cur.escrow i - a),
                     phase := upd d.cur.phase t Phase.inflight, amt := upd d.cur.amt t a,
                     dest := upd d.cur.dest t j } := Step.send d.cur i j t a hi hj ht hcun hcle
    have std : Step rs ts d.dur
        { d.dur with escrow := upd d.dur.escrow i (d.dur.escrow i - a),
                     phase := upd d.dur.phase t Phase.inflight, amt := upd d.dur.amt t a,
                     dest := upd d.dur.dest t j } := Step.send d.dur i j t a hi hj ht hdun hdle
    have hAc := A_preserved hrn htn hdc stc
    have hAd := A_preserved hrn htn hdd std
    exact ⟨Bound_of_A_eq hAc hbc, Bound_of_A_eq hAd hbd,
           destOk_preserved hdc stc, destOk_preserved hdd std⟩
  | recv t ht hcin hdin =>
    have stc : Step rs ts d.cur
        { d.cur with escrow := upd d.cur.escrow (d.cur.dest t) (d.cur.escrow (d.cur.dest t) + d.cur.amt t),
                     phase := upd d.cur.phase t Phase.received } := Step.recv d.cur t ht hcin
    have std : Step rs ts d.dur
        { d.dur with escrow := upd d.dur.escrow (d.dur.dest t) (d.dur.escrow (d.dur.dest t) + d.dur.amt t),
                     phase := upd d.dur.phase t Phase.received } := Step.recv d.dur t ht hdin
    have hAc := A_preserved hrn htn hdc stc
    have hAd := A_preserved hrn htn hdd std
    exact ⟨Bound_of_A_eq hAc hbc, Bound_of_A_eq hAd hbd,
           destOk_preserved hdc stc, destOk_preserved hdd std⟩
  | persist => exact ⟨hbc, hbc, hdc, hdc⟩      -- dur := cur
  | crash   => exact ⟨hbd, hbd, hdd, hdd⟩      -- cur := dur (safe BECAUSE durable is bounded)
  | drop    => exact ⟨hbc, hbd, hdc, hdd⟩
  | noop    => exact ⟨hbc, hbd, hdc, hdd⟩

end Escrow
