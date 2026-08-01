#!/usr/bin/env bash
# Run the unit tests under GUT, with a watchdog.
#
# A script that fails to parse never reaches GUT's exit call, so the run would
# sit there forever rather than failing - hence the timeout.
#
# Usage: scripts/test.sh <godot-binary> [timeout-seconds] [extra gut args...]

set -uo pipefail

GODOT="${1:?usage: test.sh <godot-binary> [timeout-seconds] [gut args...]}"
TIMEOUT="${2:-180}"
[ "$#" -ge 1 ] && shift
[ "$#" -ge 1 ] && shift
EXTRA=("$@")

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd \
	-gdir=res://test/unit -gexit ${EXTRA[@]+"${EXTRA[@]}"} > "$log" 2>&1 &
pid=$!

waited=0
while kill -0 "$pid" 2>/dev/null; do
	sleep 1
	waited=$((waited + 1))
	if [ "$waited" -ge "$TIMEOUT" ]; then
		kill -9 "$pid" 2>/dev/null || true
		cat "$log"
		echo
		echo "FAILED: tests did not finish within ${TIMEOUT}s (hung?)"
		exit 1
	fi
done

wait "$pid"
status=$?
cat "$log"

# GUT exits non-zero on failure, but a script error can stop a test before it
# ever asserts, so treat engine errors as failures too.
if grep -qE 'SCRIPT ERROR|Parse Error' "$log"; then
	echo
	echo "FAILED: engine errors during the run (see above)"
	exit 1
fi

exit $status
