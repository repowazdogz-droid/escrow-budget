# escrow-budget — Floor A/B/C verification targets.
.PHONY: tlc tlc-adversarial tlc-c impl impl-c check clean

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

## check: full A+B+C gate.
check: tlc tlc-adversarial impl tlc-c impl-c
	@echo "=================================================="
	@echo "FLOOR A+B+C: model-checked + reference impl + distributed impl"
	@echo "  A/B: correct PASSES, broken CAUGHT; 5/5 reference mutants killed"
	@echo "  C:   4-config matrix confirms receiver-idemp is cap-safety-critical,"
	@echo "       sender-idemp is conservation-only; PBT green; 4/4 mutants killed"
	@echo "=================================================="

clean:
	@rm -rf spec/states impl/__pycache__ .pytest_cache
