#!/usr/bin/env bash
# Run TLC on a spec module using the PINNED TLA+ Tools (v1.7.4). The jar is not committed;
# it is downloaded on demand from the official release and verified against the committed
# SHA-256 (tools/tla2tools.jar.sha256). Exits with TLC's own exit code (non-zero on an
# invariant violation) so callers can assert the expected outcome.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
JAR="$ROOT/tools/tla2tools.jar"
SHA_FILE="$ROOT/tools/tla2tools.jar.sha256"
TLA_VERSION="v1.7.4"
TLA_URL="https://github.com/tlaplus/tlaplus/releases/download/${TLA_VERSION}/tla2tools.jar"

MODULE="${1:?usage: run-tlc.sh MODULE [CONFIG]}"
CONFIG="${2:-$MODULE}"

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else echo ""; fi
}

[ -f "$SHA_FILE" ] || { echo "run-tlc: missing $SHA_FILE"; exit 2; }
EXPECTED="$(awk '{print $1}' "$SHA_FILE")"

if [ ! -f "$JAR" ]; then
  command -v curl >/dev/null 2>&1 || { echo "run-tlc: no curl to fetch tla2tools"; exit 2; }
  echo "run-tlc: fetching pinned TLA+ Tools $TLA_VERSION ..."
  curl -fsSL -o "$JAR" "$TLA_URL" || { echo "run-tlc: download failed"; rm -f "$JAR"; exit 2; }
fi
ACTUAL="$(sha256_of "$JAR")"
[ -n "$ACTUAL" ] || { echo "run-tlc: no sha256 tool available"; exit 2; }
if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "run-tlc: tla2tools.jar SHA-256 MISMATCH"; echo "  expected $EXPECTED"; echo "  actual   $ACTUAL"; exit 2
fi

JAVA=""
for c in "$(/usr/libexec/java_home 2>/dev/null)/bin/java" \
         $(ls /opt/homebrew/opt/openjdk*/bin/java 2>/dev/null) \
         "$(command -v java 2>/dev/null)"; do
  if [ -n "$c" ] && "$c" -version >/dev/null 2>&1; then JAVA="$c"; break; fi
done
[ -n "$JAVA" ] || { echo "run-tlc: no working JDK -> cannot run TLC"; exit 2; }

cd "$ROOT/spec"
echo "run-tlc: $("$JAVA" -version 2>&1 | head -1) — TLC on $MODULE (config ${CONFIG}.cfg)"
# -deadlock: do NOT treat terminal states as errors. This is a SAFETY-only artefact; we make
# no liveness/availability claim, so a reachable state with no enabled action (all budget spent
# or lost) is expected and must not mask invariant checking of the full reachable state space.
exec "$JAVA" -XX:+UseParallelGC -cp "$JAR" tlc2.TLC -deadlock -config "${CONFIG}.cfg" -cleanup "${MODULE}.tla"
