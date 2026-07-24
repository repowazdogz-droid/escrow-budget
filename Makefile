# escrow-budget — Floor A/B/C/D/E + theory-checkpoint + Floor F1 (Lean) verification targets.
.PHONY: tlc tlc-adversarial tlc-c tlc-d theory apalache-inductive impl impl-c impl-d impl-theory impl-e stress lean check clean
LEANPATH := $(HOME)/.elan/bin

## tlc: bounded model-check the CORRECT escrow protocol; invariants must hold.
tlc:
	@bash scripts/run-tlc.sh EscrowBudget EscrowBudget

## tlc-adversarial: the deliberately-broken model MUST be caught by TLC (guards against a vacuous green).
tlc-adversarial:
	@out="$$(bash scripts/run-tlc.sh EscrowBudgetBad EscrowBudgetBad 2>&1 || true)"; \
	 echo "$$out" | grep -E 'is violated|Error:|distinct states found|states generated' | tail -6; \
	 if echo "$$out" | grep -q 'is violated'; then \
	   echo "ADVERSARIAL: OK — TLC caught the injected duplicate-credit bug"; \
	 else \
	   echo "ADVERSARIAL: FAIL — TLC did NOT catch the injected bug"; exit 1; fi

## impl: Floor B — executable reference implementation: tests + mutation testing.
impl:
	@python3 impl/test_escrow.py
	@python3 impl/mutation_check.py

## tlc-c: Floor C — distributed model evidence matrix (assumption necessity, both directions).
tlc-c:
	@bash scripts/floorC-matrix.sh

## impl-c: Floor C — distributed impl: property-based tests + adversarial replays + mutation.
impl-c:
	@python3 impl/test_distributed.py
	@python3 impl/mutation_distributed.py

## tlc-d: Floor D — crash/recovery/partition matrix (refutation hunt + both crash safety-faults).
tlc-d:
	@bash scripts/floorD-matrix.sh

## impl-d: Floor D — crash/recovery impl: PBT with crashes + adversarial replays + mutation.
impl-d:
	@python3 impl/test_durable.py
	@python3 impl/mutation_durable.py

## theory: checkpoint — Safety vs Non-creation vs Conservation are distinct (model-checked).
theory:
	@bash scripts/theory-matrix.sh

## apalache-inductive: certify the inductive certificates with Apalache (symbolic/SMT).
## NOT part of `make check` — Apalache is up to 200x slower than TLC on these specs and is a
## manual, occasional check. TLC proves invariants TRUE on reachable states; only Apalache can
## show they are INDUCTIVE. Requires Apalache + a JDK; exits 2 if absent.
apalache-inductive:
	@bash scripts/apalache-inductive.sh

## impl-theory: checkpoint — executable safety cert under safe recovery + the four distinctions.
impl-theory:
	@python3 impl/test_recovery.py

## impl-e: Floor E — gate-sized hostile harness + differential + teeth + falsification probe.
impl-e:
	@python3 impl/spec_model.py
	@python3 impl/test_floor_e.py

## stress: Floor E — the full 10,000-execution hostile fault-injection run (slow, ~90s).
stress:
	@python3 impl/fault_harness.py 10000

## lean: Floors F1+F2 — build the Lean proofs, scan for placeholders, and audit axioms.
lean:
	@if grep -RnE '\bsorry\b|\badmit\b|native_decide|^[[:space:]]*axiom ' lean/Escrow lean/Escrow.lean; then \
	   echo "PLACEHOLDER SCAN: FAIL — sorry/admit/native_decide/axiom found"; exit 1; \
	 else echo "PLACEHOLDER SCAN: OK — no sorry/admit/native_decide/project axiom"; fi
	@cd lean && PATH="$(LEANPATH):$$PATH" lake build
	@cd lean && PATH="$(LEANPATH):$$PATH" lake env lean Escrow/Audit.lean 2>/dev/null | tee .axioms.txt
	@if grep -qiE 'sorryAx|Classical\.choice|ofReduceBool' lean/.axioms.txt; then \
	   echo "AXIOM AUDIT: FAIL — sorry/Classical/reduceBool axiom present"; exit 1; \
	 else echo "AXIOM AUDIT: OK — F1+F2 headline theorems use only [propext, Quot.sound]"; fi

## check: full A+B+C+D+E + theory + Floor F1 (Lean) gate.
check: tlc tlc-adversarial impl tlc-c impl-c tlc-d impl-d theory impl-theory impl-e lean
	@echo "=================================================="
	@echo "FLOOR A+B+C+D + THEORY: model-checked + reference + distributed + crash/recovery"
	@echo "  A/B: correct PASSES, broken CAUGHT; 5/5 reference mutants killed"
	@echo "  C:   receiver-idemp cap-safety-critical, sender-idemp conservation-only; 4/4 mutants"
	@echo "  D:   crash refutation hunt survives; lazy-debit (SENDER)+volatile-recvd both CREATE"
	@echo "       budget -> 'receiver-side only' REFUTED, creation/destruction law holds; 3/3 mutants"
	@echo "  THEORY: Safety (A<=CAP) != Non-creation (A'<=A) != Conservation (A'=A); safe reclaim"
	@echo "          raises A within headroom (D refuted); local rule is A'<=CAP, not A'<=A"
	@echo "  E:   differential 66==66 vs TLC; hostile harness holds; broken caught; 12/12 mutants"
	@echo "       (full 10,000-execution run: make stress)"
	@echo "  F1:  Lean 4 machine proof of CRASH-FREE safety for arbitrary finite replica sets;"
	@echo "       WF /\\ InFlightNonneg /\\ Bound inductive; axioms [propext, Quot.sound]; no sorry."
	@echo "  F2:  Lean 4 machine proof of CRASH/RECOVERY safety (disciplined, global crash);"
	@echo "       joint Bound-cur /\\ Bound-dur invariant; write-ahead + durable-dedup load-bearing."
	@echo "=================================================="

clean:
	@rm -rf spec/states impl/__pycache__ .pytest_cache
