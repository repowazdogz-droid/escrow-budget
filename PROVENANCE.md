# PROVENANCE.md

## What this artefact is

A self-contained verification artefact for a distributed escrow/budget protocol: TLA+ models
checked with TLC, an executable Python model exercised by deterministic + property-based tests and
fault injection, and Lean 4 machine proofs of the crash-free and crash/recovery safety theorems.

## How it was built

Developed in floors A–G (see `RELEASE-NOTES.md`), each floor gated by `make check`:

- **A** reproducible TLA+ toolchain + first protocol model; **B** executable reference; **C**
  distributed model + separation of safety from conservation; **D** crash/recovery + partitions;
  a **theory checkpoint** de-conflating safety / non-creation / conservation; **E** hostile
  fault-injection harness + differential vs TLA+; **F1** Lean crash-free proof; **F2** Lean
  crash/recovery proof; **G** release audit + documentation.

The development record, including refuted hypotheses and corrected overstatements, is preserved in
`SCOPE.md` and `RELEASE-NOTES.md` rather than silently rewritten.

## What it reuses

- The **pinned-TLA+-toolchain pattern** (download-on-demand + SHA-256 verification) and the
  **conserved-quantity design philosophy** from the public predecessor artefact `capctl-iris`
  (a shared-memory concurrent capability meter in Iris/Rocq). Only the *pattern* and *philosophy*
  are reused; no code from that project is included here.

## Pinned versions

- TLA+ Tools **v1.7.4** (SHA-256 in `tools/tla2tools.jar.sha256`; downloaded on demand, not committed).
- Lean toolchain **`leanprover/lean4:v4.32.0`** (`lean/lean-toolchain`); mathlib-free.
- Python 3 + Hypothesis (import-checked at test time).

## Independent review

Before release, an independent external-style review was run using **local** inference models only
(the MLX server's Qwen3-30B and Ollama's qwen2.5-coder-14b); cloud APIs were treated as
unauthorised and not used. Every reviewer objection was verified directly against source; findings
and dispositions are recorded in `CLAIMS-AUDIT.md`. Reviewer output was treated as hypotheses, not
evidence.

## Authorship

Built with AI assistance (Claude). Commit trailers record co-authorship. Licensed MIT (`LICENSE`).
