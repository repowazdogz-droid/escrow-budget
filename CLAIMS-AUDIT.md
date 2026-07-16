# CLAIMS-AUDIT.md

Every public claim, mapped to exactly one evidence category. No claim is left unmapped. Overstatements
found during the Floor-G hostile audit are listed with the wording change applied.

Evidence categories: **Lean proof** · **TLC bounded** · **Python deterministic** · **Hypothesis
property** · **mutation** · **differential (bounded)** · **documented assumption** · **explicit
non-claim**.

## The ten flagged claims

| # | Claim | Mapped to | Verdict |
|---|---|---|---|
| 1 | "arbitrary finite replica and transfer sets" | **Lean proof** (`reachable_safe`, `durable_reachable_safe` quantify over any `rs`/`ts : List` with `Nodup`) | OK — literally arbitrary finite; **static** roster (join/leave is an explicit non-claim) |
| 2 | "crash/recovery safety" | **Lean proof** (`durable_reachable_safe`) + **TLC** + **Hypothesis** | OK for the **disciplined, global-crash** model; per-replica crash is TLC+Python only (non-claim in Lean) |
| 3 | "message loss, duplication, retry, reordering" | **Lean proof** (network via drop/duplicate-refusal/interleaving) + **TLC** + **Hypothesis** | OK — all four modelled; "duplication"/"retry" handled by dedup guards |
| 4 | "write-ahead debit is load-bearing" | **Lean mutation** (removing it breaks `Jinv_preserved`) | OK — machine-checked load-bearing |
| 5 | "durable receiver dedup is load-bearing" | **Lean mutation** (removing it breaks `Jinv_preserved`) | OK — machine-checked load-bearing |
| 6 | "all interleavings" | **Lean proof** (all executions, unbounded) for the abstract protocol; **TLC** (bounded) for the concrete models | OK if scoped: Lean = all interleavings of the abstract model; TLC = bounded |
| 7 | "unbounded" | **Lean proof** (arbitrary finite N; not a fixed config) | OK — refers to Lean's all-N quantification, explicitly distinguished from bounded TLC |
| 8 | "implementation conforms to TLA+" | **differential (bounded)** only (66-state match, one config) | **Corrected** — never state "conforms"/"refines"; wording is now "bounded state-space agreement only" |
| 9 | "machine-verified distributed service" | — | **Corrected** — it is a machine-verified **protocol** + models, **not a service**. "service" removed. |
| 10 | conservation / liveness / availability wording | **explicit non-claim** | conservation is **not** the safety claim; liveness/availability/fairness explicitly disclaimed |

## Overstatements found and fixed (smallest wording change; no proof was strengthened to save language)

1. **"verified distributed budget *service*"** → **"formally verified distributed budget
   *protocol*"** + an explicit line that this is a verification artefact, not a production service.
2. **Headline "the cap is a *conserved quantity*"** → safety is the **bound** `A ≤ CAP`;
   conservation (`= CAP`) is a *separate* property, **not** the safety claim, and **not** preserved
   under crashes/loss. Corrected in README and reinforced in `SCOPE.md`.
3. **"differential *conformance*"** wording → "bounded state-space agreement only" everywhere; no
   refinement is claimed.
4. **Lean "axioms" phrasing** → standardised to "zero project-defined axioms and no `sorry`;
   headline proofs depend on Lean's standard `propext` and `Quot.sound`" (never "axiom-free").
5. **Added explicit non-claims** that were true but unwritten: **static replica membership**,
   **no Byzantine model**, **global-crash scope stated wherever crash safety is claimed**.

## Independent reviewer findings (local models; treated as hypotheses, verified against source)

Five isolated reviewer roles (formal / distributed-systems / TCB-assumptions / docs-consistency /
hostile-reject). Models used: **MLX Qwen3-30B** (4 roles) and **Ollama qwen2.5-coder-14b** (1 role).
Disposition of every distinct objection:

| Objection | Verified verdict |
|---|---|
| "InFlightNonneg not enforced / allows negative" | **False** — amounts are `Nat`, `InFlight ≥ 0` by construction (`inflightNonneg_all`); `ℤ` phrasing is deliberate. Doc clarified. |
| "certificate over `Int` violates escrow≥0" | **Misread** — `Int` makes `WF`/`InFlightNonneg` explicit load-bearing hypotheses; protocol instantiates with `Nat`. |
| "global vs per-replica crash" | **Already disclosed** scope limit; now stated wherever crash safety is claimed. |
| "no machine-checked refinement undermines cross-verification" | **Already disclosed**; `MODEL-CORRESPONDENCE.md` states it plainly. |
| "CAP=0 unhandled / division by zero" | **Non-issue** — `CAP=0` is proved (no division anywhere). |
| "concurrent transfers unproved" | **Non-issue** — concurrency = interleaved transitions; the proof covers all interleavings. |
| "negative amounts" | **Non-issue** — amounts are `Nat`. |
| "dynamic/large-scale replicas" | Large scale covered (all finite N); **dynamic membership** now an explicit non-claim. |

**No reviewer objection survived verification as a genuine defect.** The useful ones were
documentation clarifications, applied above. Reviewer capability was limited (small local models,
no source access, resource-constrained — see below).

### Independent-review disclosure

- **Models used:** MLX `Qwen3-30B-A3B-4bit` (server on :8080), Ollama `qwen2.5-coder:14b`.
- **Models unavailable:** Ollama `hermes3:8b`, `gemma3:12b`, `qwen3:14b`, `deepseek-r1:32b`,
  `qwen3:32b` — their runners were killed by **memory pressure** while the MLX 30B model held RAM
  (Ollama serves one model at a time). Re-routed those roles to the MLX model.
- **Blocked / not used:** cloud APIs (Anthropic/OpenAI/Gemini keys were present but treated as
  **unauthorised** for sending artefact content off-machine, consistent with the project's
  data-exfiltration boundary).
- **Reviewer limitations:** reviewers saw only an objective evidence packet, not the source; their
  outputs were hypotheses only and every one was checked against the repository.
