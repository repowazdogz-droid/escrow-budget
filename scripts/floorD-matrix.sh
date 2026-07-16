#!/usr/bin/env bash
# Floor D evidence matrix: crash / recovery / durable-vs-volatile / partition / retransmit.
#
#   config                          invariant   expected   meaning
#   EscrowBudgetD                   Safety+Le   HOLD       refutation hunt: no crash/partition
#                                                          interleaving breaks safety (structural law survives)
#   EscrowBudgetD_Conserved         Conserved   VIOLATED   crashes DESTROY budget (safe, not conserving)
#   EscrowBudgetD_LazyDebit         SafetyLe    VIOLATED   SENDER-side crash CREATES budget
#                                                          (falsifies "receiver-side only")
#   EscrowBudgetD_VolatileRecvd     SafetyLe    VIOLATED   receiver double-credit across a crash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"

check() { # <config> <hold|violated>
  local cfg="$1" want="$2" out got="unknown"
  out="$(bash scripts/run-tlc.sh EscrowBudgetD "$cfg" 2>&1)"
  echo "$out" | grep -q "No error has been found" && got="hold"
  echo "$out" | grep -q "is violated"            && got="violated"
  if [ "$got" = "$want" ]; then printf "  OK    %-30s expected %-8s got %s\n" "$cfg" "$want" "$got"
  else printf "  FAIL  %-30s expected %-8s got %s\n" "$cfg" "$want" "$got"; return 1; fi
}

rc=0
echo "Floor D evidence matrix (TLC):"
check EscrowBudgetD              hold     || rc=1
check EscrowBudgetD_Conserved    violated || rc=1
check EscrowBudgetD_LazyDebit    violated || rc=1
check EscrowBudgetD_VolatileRecvd violated || rc=1
if [ "$rc" -eq 0 ]; then
  echo "MATRIX: OK — no crash/partition interleaving breaks safety under discipline; both crash"
  echo "             safety-faults (lazy-debit, volatile-recvd) CREATE budget; crashes otherwise"
  echo "             only DESTROY it. 'Receiver-side only' is refuted; creation/destruction law holds."
else
  echo "MATRIX: FAIL — an expected outcome flipped"
fi
exit "$rc"
