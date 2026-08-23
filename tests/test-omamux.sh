#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OMAMUX="$ROOT/scripts/omamux"
TEST_ROOT=$(mktemp -d)
SOCKET="omamux-test-$$"
CAPTURE="$TEST_ROOT/terminal-args"
export XDG_STATE_HOME="$TEST_ROOT/state"
export TMUX_TMPDIR="$TEST_ROOT/tmux"
export OMAMUX_TMUX_SOCKET="$SOCKET"
export OMAMUX_TERMINAL_LAUNCHER="$TEST_ROOT/fake-terminal"

cleanup() {
  tmux -L "$SOCKET" kill-server 2>/dev/null || true
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_json() {
  local json=$1 filter=$2 message=$3
  jq -e "$filter" <<<"$json" >/dev/null || fail "$message\n$json"
}

mkdir -p "$TEST_ROOT/tmux"
chmod 700 "$TEST_ROOT/tmux"

cat >"$OMAMUX_TERMINAL_LAUNCHER" <<'LAUNCHER'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${OMAMUX_TEST_CAPTURE:?}"
LAUNCHER
chmod +x "$OMAMUX_TERMINAL_LAUNCHER"
export OMAMUX_TEST_CAPTURE="$CAPTURE"

empty=$($OMAMUX list)
assert_json "$empty" '.ok and .tmux.available and (.sessions | length == 0)' \
  "list should treat a missing tmux server as an empty list"

tmux -L "$SOCKET" new-session -d -s alpha
tmux -L "$SOCKET" new-window -d -t '=alpha'
first_alpha_window=$(tmux -L "$SOCKET" list-windows -t '=alpha' -F '#{window_id}' | head -n 1)
tmux -L "$SOCKET" split-window -d -t "$first_alpha_window"
tmux -L "$SOCKET" new-session -d -s beta

listed=$($OMAMUX list)
assert_json "$listed" '.sessions | length == 2' "list should return both isolated sessions"
assert_json "$listed" 'any(.sessions[]; .name == "alpha" and .windows == 2 and .attachedClients == 0)' \
  "list should return tmux metadata"
assert_json "$listed" 'all(.sessions[]; (.nativeOrder | type) == "number")' \
  "list should expose tmux native order for optimistic placement"

detail=$($OMAMUX detail alpha)
assert_json "$detail" '.ok and .session == "alpha" and (.windows | length == 2)' \
  "detail should group panes into both windows"
assert_json "$detail" '([.windows[].panes[]] | length) == 3' \
  "detail should return every pane in the session"
assert_json "$detail" 'all(.windows[].panes[]; (.id | startswith("%")) and (.command | length > 0))' \
  "detail should return pane identity and command metadata"

$OMAMUX favorite toggle alpha >/dev/null
starred=$($OMAMUX list)
assert_json "$starred" '.sessions[0].name == "alpha" and .sessions[0].favorite' \
  "a favorite should move to the top"

$OMAMUX favorite toggle beta >/dev/null
starred=$($OMAMUX list)
assert_json "$starred" '.sessions[0].name == "beta" and .sessions[1].name == "alpha"' \
  "a newly starred session should become the first favorite"

$OMAMUX favorite reorder alpha beta >/dev/null
reordered=$($OMAMUX list)
assert_json "$reordered" '.sessions[0].name == "alpha" and .sessions[1].name == "beta"' \
  "favorite reorder should persist display order"

tmux -L "$SOCKET" kill-session -t '=alpha'
hidden=$($OMAMUX list)
assert_json "$hidden" '(.sessions | length == 1) and .sessions[0].name == "beta"' \
  "missing favorite sessions should stay out of the live list"
tmux -L "$SOCKET" new-session -d -s alpha
restored=$($OMAMUX list)
assert_json "$restored" '.sessions[0].name == "alpha" and .sessions[0].favorite' \
  "recreated sessions should recover their favorite position"

$OMAMUX attach alpha >/dev/null
mapfile -t attach_args <"$CAPTURE"
[[ ${attach_args[*]} == *"attach-session -t =alpha"* ]] \
  || fail "attach should launch an exact tmux target"

$OMAMUX create 'client work; echo safe' >/dev/null
tmux -L "$SOCKET" has-session -t '=client work; echo safe' \
  || fail "create should pass metacharacters as a literal session name"
mapfile -t create_args <"$CAPTURE"
[[ ${create_args[*]} == *"attach-session -t =client work; echo safe"* ]] \
  || fail "create should attach to the exact new session name"

if $OMAMUX create 'bad.name' >/dev/null; then
  fail "create should reject dots in session names"
fi
if $OMAMUX favorite reorder alpha alpha >/dev/null; then
  fail "favorite reorder should reject duplicates"
fi

printf '{not-json\n' >"$XDG_STATE_HOME/omamux/favorites.json"
if $OMAMUX list >/dev/null; then
  fail "malformed state should be reported rather than overwritten"
fi
grep -q '{not-json' "$XDG_STATE_HOME/omamux/favorites.json" \
  || fail "malformed state should be preserved"

printf 'PASS: omamux backend\n'
