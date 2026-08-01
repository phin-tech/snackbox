#!/usr/bin/env bash
# Run the headless smoke suite under a watchdog.
#
# The suite quits the engine itself when it finishes. That means a script which
# fails to parse never reaches quit(), and a plain run would sit there forever
# instead of failing - so the timeout is not optional here.
#
# Usage: scripts/test.sh <godot-binary> [timeout-seconds]

set -euo pipefail

GODOT="${1:?usage: test.sh <godot-binary> [timeout-seconds]}"
TIMEOUT="${2:-180}"

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

"$GODOT" --headless --path . res://tests/smoke.tscn > "$log" 2>&1 &
pid=$!

waited=0
while kill -0 "$pid" 2>/dev/null; do
	sleep 1
	waited=$((waited + 1))
	if [ "$waited" -ge "$TIMEOUT" ]; then
		kill -9 "$pid" 2>/dev/null || true
		cat "$log"
		echo
		echo "FAILED: test run did not finish within ${TIMEOUT}s (hung?)"
		echo "A parse error will do this - the suite never reaches quit()."
		exit 1
	fi
done

wait "$pid" || true
cat "$log"

# The suite reports its own failures, but a script error can abort a test before
# it records anything, so any engine error counts as a failure regardless of
# what the suite printed.
if grep -qE 'SCRIPT ERROR|Parse Error|ERROR:' "$log"; then
	echo
	echo "FAILED: engine errors during the test run (see above)"
	exit 1
fi

if ! grep -q 'OK: all smoke tests passed' "$log"; then
	echo
	echo "FAILED: the suite did not report success"
	exit 1
fi
