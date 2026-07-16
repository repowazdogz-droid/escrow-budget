# CONTRIBUTING

This is a verification artefact. Two rules keep it trustworthy:

1. **Every change must keep `make check` green** — TLA+ (positive models + negative controls),
   Python (deterministic + property + mutation), Lean F1/F2, the placeholder scan, and the axiom
   audit. Also verify from a clean cache: `rm -rf lean/.lake && make clean && make check`.

2. **No claim without an evidence grade.** If you add a claim to any doc, map it in
   `CLAIMS-AUDIT.md` / `THEOREM-INDEX.md` to one of: Lean proof · TLC bounded · Python test ·
   Hypothesis property · mutation · bounded differential · documented assumption · explicit
   non-claim. Never describe a bounded/tested result as a proof, never call the Lean result
   "axiom-free" (say "zero project-defined axioms; depends on `propext`, `Quot.sound`"), and never
   claim refinement between the tools.

## Layout

- `spec/` — TLA+ models + configs (`*.cfg`); `scripts/*.sh` drive TLC and the matrices.
- `impl/` — executable Python model, tests, fault harness, mutation suites, differential.
- `lean/Escrow/` — Lean 4 proofs (mathlib-free); `Escrow/Audit.lean` prints the axiom footprint.
- `Makefile` — one-command verification (`make check`); `make lean`, `make stress` for parts.

## Toolchain

JDK (TLC), `curl` (fetches the pinned checksummed TLA+ Tools jar — not committed), Python 3 +
`hypothesis`, and `elan`/`lake` (Lean toolchain pinned in `lean/lean-toolchain`). No other network
dependency.
