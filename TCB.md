# TCB.md — Trusted Computing Base

What you must trust for each claim to hold. Nothing here is proved by the artefact itself; these
are the foundations the evidence rests on.

## For the Lean machine proofs (`reachable_safe`, `durable_reachable_safe`)

- **The Lean 4 kernel** (toolchain pinned in `lean/lean-toolchain` = `leanprover/lean4:v4.32.0`).
- **Lean's standard axioms actually used**: `propext` and `Quot.sound` (exactly what
  `#print axioms` reports for every headline theorem; audited by `make lean`). `Classical.choice`
  is **not** used; there are **no project-defined axioms** and **no `sorry`**.
- **No external libraries.** The Lean development is mathlib-free — it depends only on Lean core.
- **The theorem statements themselves.** A proof is only as meaningful as what it states; the exact
  statements, their quantifiers, and their assumptions are in `THEOREM-INDEX.md`. In particular you
  must accept that the Lean `State`/`DState` transition system is a faithful abstraction of the
  intended protocol — this faithfulness is argued (`MODEL-CORRESPONDENCE.md`), **not** machine-proved.

## For the TLA+ model-checking results

- **TLC** and the **TLA+ language semantics** (TLA+ Tools **v1.7.4**).
- **Pinned + checksum-verified toolchain**: `scripts/run-tlc.sh` downloads exactly v1.7.4 and
  verifies it against the committed SHA-256 in `tools/tla2tools.jar.sha256` before running.
- **A JVM** to run TLC.
- Results are **bounded** (small finite configurations). They are evidence, not proof for all N.

## For the Python executable-model results

- **CPython 3** and the **Hypothesis** property-testing library.
- The Python code is an **executable model**, trusted only as a cross-check; no claim rests on it
  alone. Results are **tested**, not proved.

## For reproducibility / supply chain

- **`curl`** and network access to GitHub **once** to fetch the pinned TLA+ Tools jar (then
  checksum-verified). No other network dependency. The jar is **not** committed.
- **`elan`/`lake`** to build Lean (toolchain pinned; no third-party Lean packages).
- **`make`** and a POSIX shell to drive `make check`.

## Explicitly NOT trusted / NOT in scope

- No hardware, TEE, or clock assumptions.
- No trust in message delivery: the network may reorder, duplicate, lose, and delay arbitrarily.
- No trust that replicas are honest beyond following the protocol — Byzantine behaviour is **out of
  scope** (see `SCOPE.md`).
- No machine-checked link between the three tools (Lean/TLA+/Python); their agreement is only
  bounded-checked (`MODEL-CORRESPONDENCE.md`).
