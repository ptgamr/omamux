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
export OMAMUX_HYPRCTL_BIN="$TEST_ROOT/fake-hyprctl"
export OMAMUX_TEST_HYPR_CAPTURE="$TEST_ROOT/hyprctl-args"

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

cat >"$OMAMUX_HYPRCTL_BIN" <<'HYPRCTL'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == clients && ${2:-} == -j ]]; then
  if [[ -n ${OMAMUX_TEST_HYPR_PID:-} ]]; then
    jq -cn --argjson pid "$OMAMUX_TEST_HYPR_PID" '[{
      address: "0xabc123",
      pid: $pid,
      class: "foot",
      title: "tmux",
      workspace: {id: 7, name: "7"}
    }]'
  else
    printf '[]\n'
  fi
  exit
fi
if [[ ${1:-} == dispatch ]]; then
  printf '%s\n' "$*" >"${OMAMUX_TEST_HYPR_CAPTURE:?}"
  printf 'ok\n'
  exit
fi
exit 1
HYPRCTL
chmod +x "$OMAMUX_HYPRCTL_BIN"

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

target_window=$(tmux -L "$SOCKET" list-windows -t '=alpha' -F '#{window_index}' | tail -n 1)
target_pane=$(tmux -L "$SOCKET" list-panes -t "=alpha:$target_window" -F '#{pane_id}' | head -n 1)
$OMAMUX attach alpha "$target_window" "$target_pane" >/dev/null
active_target=$(tmux -L "$SOCKET" display-message -p -t "$target_pane" \
  '#{window_active}	#{pane_active}')
[[ $active_target == 1$'\t'1 ]] \
  || fail "targeted attach should select the requested window and pane"
if $OMAMUX attach alpha 99 >/dev/null; then
  fail "targeted attach should reject a missing window"
fi

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

$OMAMUX rename alpha alpha-renamed >/dev/null
tmux -L "$SOCKET" has-session -t '=alpha-renamed' \
  || fail "rename should update the exact tmux session"
if tmux -L "$SOCKET" has-session -t '=alpha' 2>/dev/null; then
  fail "rename should remove the previous tmux session name"
fi
renamed=$($OMAMUX list)
assert_json "$renamed" '.sessions[0].name == "alpha-renamed" and .sessions[0].favorite' \
  "rename should preserve favorite identity and order"
$OMAMUX rename alpha-renamed alpha >/dev/null

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

script -qefc "tmux -L '$SOCKET' attach-session -t '=alpha'" /dev/null \
  >/dev/null 2>&1 &
hypr_owner_pid=$!
export OMAMUX_TEST_HYPR_PID=$hypr_owner_pid
for _ in {1..40}; do
  [[ $(tmux -L "$SOCKET" list-clients -t '=alpha' 2>/dev/null | wc -l) -gt 0 ]] && break
  sleep 0.05
done
focused=$($OMAMUX attach alpha)
assert_json "$focused" '.ok and .action == "focus" and .window.workspace.id == 7' \
  "attach should focus an existing local Hyprland window"
grep -Fqx 'dispatch hl.dsp.focus({ window = "address:0xabc123" })' \
  "$OMAMUX_TEST_HYPR_CAPTURE" \
  || fail "attach should focus the matched Hyprland address"
focused_list=$($OMAMUX list)
assert_json "$focused_list" 'any(.sessions[];
    .name == "alpha" and .desktop.workspace.id == 7 and .desktop.address == "0xabc123")' \
  "list should expose the matched local workspace"

$OMAMUX create 'client work; echo safe' >/dev/null
tmux -L "$SOCKET" has-session -t '=client work; echo safe' \
  || fail "create should pass metacharacters as a literal session name"
mapfile -t create_args <"$CAPTURE"
[[ ${create_args[*]} == *"attach-session -t =client work; echo safe"* ]] \
  || fail "create should attach to the exact new session name"

if $OMAMUX create 'bad.name' >/dev/null; then
  fail "create should reject dots in session names"
fi
if $OMAMUX rename alpha beta >/dev/null; then
  fail "rename should reject an existing session name"
fi
if $OMAMUX rename alpha 'bad.name' >/dev/null; then
  fail "rename should reject dots in session names"
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
