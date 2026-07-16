#!/usr/bin/env bash
# Theory checkpoint: model-check that Safety, Non-creation and Conservation are DISTINCT.
#
#   check                              kind        expected   what it settles
#   EscrowBudgetC / _Monotone         property    HOLD       current protocol IS non-creating
#   Recovery / _Safe                  invariant   HOLD       safety quantity (wf-free here) holds
#   Recovery / _Monotone              property    VIOLATED   safe reclaim raises A ≤ CAP (D is false)
#   Recovery / _Conservation          property    VIOLATED   loss breaks conservation, safety holds
#   Recovery / _Unsafe                invariant   VIOLATED   unguarded reclaim creates beyond CAP
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"

check() { # <module> <config> <hold|violated>
  local mod="$1" cfg="$2" want="$3" out got="unknown"
  out="$(bash scripts/run-tlc.sh "$mod" "$cfg" 2>&1)"
  echo "$out" | grep -q "No error has been found" && got="hold"
  echo "$out" | grep -q "is violated"            && got="violated"
  if [ "$got" = "$want" ]; then printf "  OK    %-28s expected %-8s got %s\n" "$cfg" "$want" "$got"
  else printf "  FAIL  %-28s expected %-8s got %s\n" "$cfg" "$want" "$got"; return 1; fi
}

rc=0
echo "Theory checkpoint (TLC): Safety vs Non-creation vs Conservation"
check EscrowBudgetC EscrowBudgetC_Monotone hold     || rc=1
check Recovery      Recovery_Safe          hold     || rc=1
check Recovery      Recovery_Monotone      violated || rc=1
check Recovery      Recovery_Conservation  violated || rc=1
check Recovery      Recovery_Unsafe        violated || rc=1
if [ "$rc" -eq 0 ]; then
  echo "THEORY: OK — the three properties are distinct. Safety (A ≤ CAP) is maintained under safe"
  echo "             recovery even though non-creation (A'≤A) and conservation (A'=A) both fail."
else
  echo "THEORY: FAIL — an expected outcome flipped"
fi
exit "$rc"
