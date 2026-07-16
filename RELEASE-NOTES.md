# RELEASE-NOTES.md

## v0.1-rc.1 — first public release candidate

First verified release of the escrow-budget distributed budget protocol: TLA+ models, an executable
Python model, and Lean 4 machine proofs of crash-free **and** disciplined crash/recovery safety, all
gated by `make check` and reproducible from an empty Lean cache.

**Headline results**

- `Escrow.reachable_safe` — machine-proved crash-free safety for arbitrary finite replica/transfer
  sets, any non-negative amounts, any CAP.
- `Escrow.durable_reachable_safe` — machine-proved crash/recovery safety (disciplined protocol,
  global crash) with write-ahead debit and durable receiver dedup proven load-bearing.
- Both depend only on Lean's standard `propext` and `Quot.sound`; zero project-defined axioms; no
  `sorry`.
- TLA+ positive models hold; all expected-negative models are negative controls that produce their
  intended counterexamples. Python: 12/12 mutants killed, 10⁴-run hostile harness holds, 66-state
  differential matches TLC.

**Scope (see README/SCOPE):** no liveness, fairness, availability, Byzantine model, or
implementation refinement; crash is global; static membership; conservation is not the safety claim.

**Floor-G audit:** hostile claim audit + independent local-model review completed; overstatements
corrected ("service"→"protocol", conservation-as-headline, differential wording, axiom phrasing);
no reviewer objection survived as a genuine defect. See `CLAIMS-AUDIT.md`.

---

## Development history (floors A–G)

Each floor was gated by `make check`; refuted hypotheses and corrected theory are preserved, not
rewritten. Full detail in `SCOPE.md`.

- **Floor A** — reproducible pinned-TLA+ toolchain (download + SHA-256 verify); first protocol model
  `EscrowBudget.tla`; `Conserved`/`Safety` invariants; a deliberately-broken model caught by TLC.
- **Floor B** — executable reference (`impl/escrow.py`); tests + mutation testing; finding: **charge
  idempotency is not required for the cap** (separate per-request property).
- **Floor C** — distributed model + impl; **separated safety (the cap, `≤`) from conservation
  (`=`)**; receiver-side dedup is the only safety-critical idempotency; sender-idemp and id-uniqueness
  are conservation-only. Verified via a TLC config matrix + PBT + mutation.
- **Floor D** — crash/recovery + partitions; **refuted** the narrow "receiver-side only" reading
  (a sender-side crash creates budget) and kept the structural creation/destruction law; write-ahead
  debit + durable receiver dedup identified as the crash-era requirements.
- **Theory checkpoint** — de-conflated **Safety** (`A ≤ CAP`) vs **non-creation** (`A' ≤ A`) vs
  **conservation** (`A' = A`); showed a safe A-increase (recovery within headroom) exists, so
  monotonicity is not the safety law; chose the certificate `WF ∧ InFlightNonneg ∧ Bound`.
- **Floor E** — hostile fault-injection harness (10⁴ composed-fault runs); differential vs TLA+
  (66-state match); mutation; **theory survived unchanged**.
- **Floor F1** — Lean 4 machine proof of crash-free safety; corrected certificate; negative controls;
  axiom audit.
- **Floor F2** — Lean 4 machine proof of crash/recovery safety; joint current/durable invariant;
  write-ahead + durable-dedup machine-checkably load-bearing; both Floor-D attacks as machine-checked
  counterexamples.
- **Floor G** — release audit: hostile claim audit, independent local-model review, secrets/privacy
  scan, reproducibility from empty caches, and this documentation set.
