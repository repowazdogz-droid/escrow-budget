# escrow-budget — Floor A verification targets.
.PHONY: tlc tlc-adversarial check clean

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

## check: full A+B gate.
check: tlc tlc-adversarial impl
	@echo "=================================================="
	@echo "FLOOR A+B: model-checked (correct PASSES, broken CAUGHT) + reference impl"
	@echo "           tests green, 5/5 mutants killed"
	@echo "=================================================="

clean:
	@rm -rf spec/states impl/__pycache__ .pytest_cache
