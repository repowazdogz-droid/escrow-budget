# escrow-budget — Floor A/B/C/D verification targets.
.PHONY: tlc tlc-adversarial tlc-c tlc-d impl impl-c impl-d check clean

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

## check: full A+B+C+D gate.
check: tlc tlc-adversarial impl tlc-c impl-c tlc-d impl-d
	@echo "=================================================="
	@echo "FLOOR A+B+C+D: model-checked + reference + distributed + crash/recovery"
	@echo "  A/B: correct PASSES, broken CAUGHT; 5/5 reference mutants killed"
	@echo "  C:   receiver-idemp cap-safety-critical, sender-idemp conservation-only; 4/4 mutants"
	@echo "  D:   crash refutation hunt survives; lazy-debit (SENDER) + volatile-recvd both CREATE"
	@echo "       budget -> 'receiver-side only' REFUTED, creation/destruction law holds; 3/3 mutants"
	@echo "=================================================="

clean:
	@rm -rf spec/states impl/__pycache__ .pytest_cache
