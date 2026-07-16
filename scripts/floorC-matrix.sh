#!/usr/bin/env bash
# Floor C evidence matrix: run EscrowBudgetC under four configs and assert the expected outcome
# of each. This is what makes the finding falsifiable — if any config flips, the build fails.
#
#   config                              invariant(s)        expected
#   EscrowBudgetC                       Safety/SafetyLe/Cons  HOLD    (correct: both idempotent)
#   EscrowBudgetC_SenderDup             Safety/SafetyLe       HOLD    (sender idemp UNNEEDED for cap)
#   EscrowBudgetC_SenderDupConserved    Conserved             VIOLATED(sender idemp needed for =CAP)
#   EscrowBudgetC_ReceiverDup           SafetyLe              VIOLATED(receiver idemp NEEDED for cap)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

check() { # <config> <hold|violated>
  local cfg="$1" want="$2"
  local out; out="$(bash scripts/run-tlc.sh EscrowBudgetC "$cfg" 2>&1)"
  local got="unknown"
  echo "$out" | grep -q "No error has been found" && got="hold"
  echo "$out" | grep -q "is violated"            && got="violated"
  if [ "$got" = "$want" ]; then
    printf "  OK    %-34s expected %-8s got %s\n" "$cfg" "$want" "$got"
  else
    printf "  FAIL  %-34s expected %-8s got %s\n" "$cfg" "$want" "$got"
    return 1
  fi
}

rc=0
echo "Floor C evidence matrix (TLC):"
check EscrowBudgetC                    hold     || rc=1
check EscrowBudgetC_SenderDup          hold     || rc=1
check EscrowBudgetC_SenderDupConserved violated || rc=1
check EscrowBudgetC_ReceiverDup        violated || rc=1
if [ "$rc" -eq 0 ]; then
  echo "MATRIX: OK — receiver-side transfer idempotency is cap-safety-critical;"
  echo "             sender-side idempotency is required only for exact conservation."
else
  echo "MATRIX: FAIL — an expected outcome flipped"
fi
exit "$rc"
