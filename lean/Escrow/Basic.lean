/-
  Escrow/Basic.lean — self-contained finite-sum toolkit (core Lean 4, no mathlib).

  Replica/transfer sets are arbitrary finite `List`s (Nodup where a single element is updated).
  `sumOver l f = Σ_{x ∈ l} f x`, `upd f k v` is a point update. We prove exactly the delta lemmas
  the safety proof needs: adding/subtracting at one point, updating off the list, and the genesis
  single-point allocation.
-/
namespace Escrow

/-- Point update of a function. -/
def upd {α : Type _} {β : Type _} [DecidableEq α] (f : α → β) (k : α) (v : β) : α → β :=
  fun x => if x = k then v else f x

@[simp] theorem upd_same {α β} [DecidableEq α] (f : α → β) (k : α) (v : β) :
    upd f k v k = v := by simp [upd]

theorem upd_ne {α β} [DecidableEq α] (f : α → β) {k x : α} (v : β) (h : x ≠ k) :
    upd f k v x = f x := by simp [upd, h]

/-- Finite sum of `f` over the list `l`. -/
def sumOver {α : Type _} (l : List α) (f : α → Nat) : Nat := (l.map f).foldr (· + ·) 0

@[simp] theorem sumOver_nil {α} (f : α → Nat) : sumOver [] f = 0 := rfl

@[simp] theorem sumOver_cons {α} (a : α) (l : List α) (f : α → Nat) :
    sumOver (a :: l) f = f a + sumOver l f := rfl

/-- Updating at a point NOT in the list leaves the sum unchanged. -/
theorem sumOver_upd_not_mem {α} [DecidableEq α] {l : List α} {k : α} (f : α → Nat) (v : Nat)
    (h : k ∉ l) : sumOver l (upd f k v) = sumOver l f := by
  induction l with
  | nil => rfl
  | cons b l ih =>
    have hb : b ≠ k := fun e => h (e ▸ List.mem_cons_self ..)
    have hl : k ∉ l := fun e => h (List.mem_cons_of_mem _ e)
    simp [sumOver_cons, upd_ne f v hb, ih hl]

/-- Adding `a` at one point raises the sum by `a`. -/
theorem sumOver_upd_add {α} [DecidableEq α] {l : List α} {k : α} (f : α → Nat) (a : Nat)
    (hk : k ∈ l) (hnd : l.Nodup) : sumOver l (upd f k (f k + a)) = sumOver l f + a := by
  induction l with
  | nil => exact absurd hk (List.not_mem_nil)
  | cons b l ih =>
    rw [List.nodup_cons] at hnd
    rcases hnd with ⟨hbl, hndl⟩
    rcases List.mem_cons.1 hk with hkb | hkl
    · -- k = b, so k ∉ l
      subst hkb
      have hnl := sumOver_upd_not_mem f (f k + a) hbl
      simp only [sumOver_cons, upd_same]
      omega
    · -- k ∈ l, so b ≠ k (since b ∉ l)
      have hbk : b ≠ k := fun e => hbl (e ▸ hkl)
      have hih := ih hkl hndl
      simp only [sumOver_cons, upd_ne f (f k + a) hbk]
      omega

/-- Subtracting `a ≤ f k` at one point lowers the sum by `a` (additive form, no truncation). -/
theorem sumOver_upd_sub {α} [DecidableEq α] {l : List α} {k : α} (f : α → Nat) (a : Nat)
    (hk : k ∈ l) (hnd : l.Nodup) (hle : a ≤ f k) :
    sumOver l (upd f k (f k - a)) + a = sumOver l f := by
  induction l with
  | nil => exact absurd hk (List.not_mem_nil)
  | cons b l ih =>
    rw [List.nodup_cons] at hnd
    rcases hnd with ⟨hbl, hndl⟩
    rcases List.mem_cons.1 hk with hkb | hkl
    · subst hkb
      have hnl := sumOver_upd_not_mem f (f k - a) hbl
      simp only [sumOver_cons, upd_same]
      omega
    · have hbk : b ≠ k := fun e => hbl (e ▸ hkl)
      have hih := ih hkl hndl
      simp only [sumOver_cons, upd_ne f (f k - a) hbk]
      omega

/-- The sum of the constant-zero function is zero. -/
@[simp] theorem sumOver_zero {α} (l : List α) : sumOver l (fun _ => 0) = 0 := by
  induction l with
  | nil => rfl
  | cons b l ih => simp [sumOver_cons, ih]

/-- Genesis single-point allocation sums to the allocated value. -/
theorem sumOver_single {α} [DecidableEq α] {l : List α} {g : α} (c : Nat)
    (hg : g ∈ l) (hnd : l.Nodup) : sumOver l (fun r => if r = g then c else 0) = c := by
  have : (fun r => if r = g then c else 0) = upd (fun _ => (0 : Nat)) g (((fun _ => (0:Nat)) g) + c) := by
    funext r; by_cases h : r = g <;> simp [upd, h]
  rw [this, sumOver_upd_add (fun _ => 0) c hg hnd]
  simp

end Escrow
