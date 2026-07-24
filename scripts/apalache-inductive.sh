#!/usr/bin/env bash
# Certify that the inductive certificates really are INDUCTIVE, using Apalache (symbolic,
# SMT-based). This is the one thing TLC structurally cannot do: TLC enumerates REACHABLE
# states, so it can tell you an invariant is TRUE, never that it is INDUCTIVE.
#
# Two obligations per certificate:
#   base   Init /\ ~Inv         unsatisfiable   ->  Init => Inv
#   step   Inv /\ Next /\ ~Inv' unsatisfiable   ->  Inv /\ Next => Inv'
# run as `--length=0` and `--length=1` respectively, with the certificate itself supplied as
# the INIT predicate for the step obligation.
#
# ############################################################################
# # WHY THIS SCRIPT ASSERTS ON THE LOG AND NOT ON THE EXIT CODE
# #
# # FAILURE MODE (observed with Apalache 0.58.3, 2026-07-24): the `--init` CLI option is
# # SILENTLY IGNORED when the .cfg file contains a `SPECIFICATION` line. Apalache emits a
# # warning when `--inv` is overridden this way, but NOT for `--init`. The run then proceeds
# # from the spec's ordinary `Init`, checks a plain one-step reachability query, prints
# # "The outcome is: NoError", and EXITS 0.
# #
# # That is indistinguishable from a successful inductiveness check by exit code alone, and
# # it produced a FALSE "Safety is inductive" result during the tool evaluation. Safety is
# # NOT inductive. The bogus pass was caught only by reading the log line that names which
# # predicate Apalache actually used.
# #
# # Therefore: every step obligation below asserts that Apalache logged
# #     "Set the initialization predicate to <CERTIFICATE>"
# # and this script exits NONZERO if that line is absent, EVEN IF Apalache exited 0.
# # Do not "simplify" this by trusting $?.
# ############################################################################
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPECDIR="$ROOT/spec/apalache"

# --- locate Apalache -------------------------------------------------------
APALACHE_BIN="${APALACHE_BIN:-}"
if [ -z "$APALACHE_BIN" ]; then
  for c in "$HOME"/wrks-tools/apalache/apalache-*/bin/apalache-mc \
           "$(command -v apalache-mc 2>/dev/null)"; do
    [ -n "$c" ] && [ -x "$c" ] && APALACHE_BIN="$c" && break
  done
fi
if [ -z "$APALACHE_BIN" ]; then
  echo "apalache-inductive: Apalache not found."
  echo "  install from https://github.com/apalache-mc/apalache/releases and/or set APALACHE_BIN"
  exit 2
fi

# Apalache needs a real JDK; a bare macOS 'java' stub is not enough.
if [ -z "${JAVA_HOME:-}" ]; then
  for j in /opt/homebrew/opt/openjdk@17 /usr/lib/jvm/java-17-openjdk "$(/usr/libexec/java_home 2>/dev/null)"; do
    if [ -n "$j" ] && [ -x "$j/bin/java" ]; then export JAVA_HOME="$j"; break; fi
  done
fi
[ -n "${JAVA_HOME:-}" ] && export PATH="$JAVA_HOME/bin:$PATH"
command -v java >/dev/null 2>&1 || { echo "apalache-inductive: no working JDK on PATH"; exit 2; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$SPECDIR"

rc=0

# cfg_for <base.cfg> <INIT-operator>  -> writes a cfg with SPECIFICATION replaced by INIT/NEXT.
# Stripping SPECIFICATION is REQUIRED: while it is present, --init is silently ignored.
cfg_for() {
  local base="$1" initop="$2" out="$3"
  grep -v -E '^[[:space:]]*(SPECIFICATION|INVARIANT|PROPERTY|INIT|NEXT)\b' "$base" > "$out"
  { echo "INIT $initop"; echo "NEXT Next"; } >> "$out"
}

# obligation <module> <basecfg> <certificate> <base|step>
obligation() {
  local mod="$1" basecfg="$2" cert="$3" kind="$4"
  local initop len cfg log t0 t1
  if [ "$kind" = "base" ]; then initop="Init"; len=0; else initop="$cert"; len=1; fi
  cfg="$WORK/${mod}_${cert}_${kind}.cfg"
  log="$WORK/${mod}_${cert}_${kind}.log"
  cfg_for "$basecfg" "$initop" "$cfg"

  t0=$(python3 -c 'import time;print(time.time())')
  "$APALACHE_BIN" check --config="$cfg" --inv="$cert" --no-deadlock --length=$len "$mod.tla" >"$log" 2>&1
  local exitcode=$?
  t1=$(python3 -c 'import time;print(time.time())')
  local secs; secs=$(python3 -c "print(f'{$t1-$t0:.1f}')")

  # ---- THE GUARD (see banner above): prove --init was honoured. ----
  if ! grep -q "Set the initialization predicate to $initop" "$log"; then
    printf "  FAIL  %-10s %-16s %-5s  --init NOT HONOURED (expected '%s'); Apalache exited %d\n" \
           "$mod" "$cert" "$kind" "$initop" "$exitcode"
    echo   "        ^ this is the silent-override trap; the exit code is NOT trustworthy here."
    grep -E "Set the initialization predicate|SPECIFICATION" "$log" | sed 's/^/        /'
    return 1
  fi

  local outcome; outcome=$(grep -oE "The outcome is: [A-Za-z]+" "$log" | head -1 | awk '{print $4}')
  if [ "$outcome" = "NoError" ]; then
    printf "  OK    %-10s %-16s %-5s  discharged   (%ss)\n" "$mod" "$cert" "$kind" "$secs"
    return 0
  else
    printf "  FAIL  %-10s %-16s %-5s  outcome=%-12s (%ss)\n" "$mod" "$cert" "$kind" "${outcome:-none}" "$secs"
    return 1
  fi
}

# --- single-candidate mode (used to drive CTI iteration) -------------------
# usage: apalache-inductive.sh <module> <cfg> <certificate> [base|step|both]
# Runs the SAME trap-guarded obligation() as the shipped certification below, so a CTI
# loop cannot accidentally bypass the --init assertion. With no arguments the script
# behaves exactly as before and certifies the two shipped certificates.
if [ "$#" -ge 3 ]; then
  MOD="$1"; CFG="$2"; CERT="$3"; KIND="${4:-both}"
  echo "Apalache single-candidate check: $MOD / $CERT  (cfg $CFG)"
  echo "  binary : $APALACHE_BIN ($("$APALACHE_BIN" version 2>/dev/null | tail -1))"
  case "$KIND" in
    base) obligation "$MOD" "$CFG" "$CERT" base || rc=1 ;;
    step) obligation "$MOD" "$CFG" "$CERT" step || rc=1 ;;
    both) obligation "$MOD" "$CFG" "$CERT" base || rc=1
          obligation "$MOD" "$CFG" "$CERT" step || rc=1 ;;
    *) echo "unknown kind: $KIND"; exit 2 ;;
  esac
  exit "$rc"
fi

echo "Apalache inductiveness certification"
echo "  binary : $APALACHE_BIN ($("$APALACHE_BIN" version 2>/dev/null | tail -1))"
echo "  NOTE   : certified at the FIXED CONSTANTS in each cfg, not for all N."
echo

echo "EscrowBudget — Inductive == TypeOK /\\ Conserved /\\ NetTidsSent"
obligation EscrowBudget EscrowBudget.cfg Inductive base || rc=1
obligation EscrowBudget EscrowBudget.cfg Inductive step || rc=1

echo
echo "Recovery — Cert == TypeOK /\\ ConservedTotal   (Bound is NOT inductive; Cert is)"
obligation Recovery Recovery_Safe.cfg Cert base || rc=1
obligation Recovery Recovery_Safe.cfg Cert step || rc=1

echo
echo "EscrowBudgetD — CertDMinimal (crash/recovery; 7 CTI rounds, see FLOORD-CTI.md)"
echo "                 9 auxiliary conjuncts. CertD, the as-iterated form, additionally"
echo "                 carries DurableRecvdSub, verified redundant given dRecvdEqRecvd."
obligation EscrowBudgetDInd EscrowBudgetD.cfg CertDMinimal base || rc=1
obligation EscrowBudgetDInd EscrowBudgetD.cfg CertDMinimal step || rc=1
obligation EscrowBudgetDInd EscrowBudgetD.cfg CertD        step || rc=1

echo
echo "NEGATIVE CONTROLS — each certificate must FAIL where the property genuinely fails."
echo "                    (if any of these passes, that check has gone vacuous)"
neg() { # <label> <module> <cfg> <cert>
  if obligation "$2" "$3" "$4" step >/dev/null 2>&1; then
    printf "  FAIL  %-34s certificate PASSED where it must not\n" "$1"; return 1
  else
    printf "  OK    %-34s failed as required\n" "$1"; return 0
  fi
}
neg "Recovery / SafeReclaim=FALSE"      Recovery         Recovery_Unsafe.cfg             Cert  || rc=1
neg "EscrowBudgetD / lazy debit"        EscrowBudgetDInd EscrowBudgetD_LazyDebit.cfg     CertDMinimal || rc=1
neg "EscrowBudgetD / volatile recvd"    EscrowBudgetDInd EscrowBudgetD_VolatileRecvd.cfg CertDMinimal || rc=1

echo
if [ "$rc" -eq 0 ]; then
  echo "INDUCTIVE: OK — all three certificates discharged, --init honoured on every step"
  echo "           obligation, and every negative control failed as required."
else
  echo "INDUCTIVE: FAIL"
fi
exit "$rc"
