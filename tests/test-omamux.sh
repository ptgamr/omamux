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
  case ${OMAMUX_TEST_HYPR_MODE:-} in
    bytes)
      head -c 2097153 /dev/zero | tr '\0' x
      exit
      ;;
    rows)
      jq -cn '[range(0; 1025) | {
        address: ("0x" + tostring),
        pid: ., class: "foot", title: "tmux",
        workspace: {id: 7, name: "7"}
      }]'
      exit
      ;;
    title)
      jq -cn '[{
        address: "0xabc123", pid: 1, class: "foot",
        title: ("x" * 1025), workspace: {id: 7, name: "7"}
      }]'
      exit
      ;;
  esac
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

FAKE_TMUX="$TEST_ROOT/fake-tmux"
cat >"$FAKE_TMUX" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == -L ]]; then
  shift 2
fi

repeat_x() {
  head -c "$1" /dev/zero | tr '\0' x
}

case ${1:-} in
  -V)
    printf 'tmux test\n'
    ;;
  has-session)
    exit 0
    ;;
  list-sessions)
    case ${OMAMUX_TEST_TMUX_MODE:-} in
      session-bytes) repeat_x 524289 ;;
      session-rows)
        for ((i = 0; i < 513; i++)); do
          printf 'session-%s\t1\t1\t0\n' "$i"
        done
        ;;
      session-name)
        printf '%s\t1\t1\t0\n' "$(repeat_x 257)"
        ;;
      *) printf 'alpha\t1\t1\t0\n' ;;
    esac
    ;;
  list-clients)
    case ${OMAMUX_TEST_TMUX_MODE:-} in
      client-bytes) repeat_x 524289 ;;
      client-rows)
        for ((i = 0; i < 1025; i++)); do
          printf 'session-%s\t1\t1\n' "$i"
        done
        ;;
      client-name)
        printf '%s\t1\t1\n' "$(repeat_x 257)"
        ;;
      *) : ;;
    esac
    ;;
  list-panes)
    case ${OMAMUX_TEST_TMUX_MODE:-} in
      pane-bytes) repeat_x 2097153 ;;
      pane-rows)
        for ((i = 0; i < 2049; i++)); do
          printf '%s\twindow\t1\t%%%s\t0\ttitle\tzsh\t/tmp\t1\n' "$i" "$i"
        done
        ;;
      window-name)
        printf '0\t%s\t1\t%%1\t0\ttitle\tzsh\t/tmp\t1\n' "$(repeat_x 513)"
        ;;
      pane-title)
        printf '0\twindow\t1\t%%1\t0\t%s\tzsh\t/tmp\t1\n' "$(repeat_x 1025)"
        ;;
      pane-command)
        printf '0\twindow\t1\t%%1\t0\ttitle\t%s\t/tmp\t1\n' "$(repeat_x 257)"
        ;;
      pane-path)
        printf '0\twindow\t1\t%%1\t0\ttitle\tzsh\t%s\t1\n' "$(repeat_x 4097)"
        ;;
      *) printf '0\twindow\t1\t%%1\t0\ttitle\tzsh\t/tmp\t1\n' ;;
    esac
    ;;
  *) exit 1 ;;
esac
TMUX
chmod +x "$FAKE_TMUX"

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
assert_json "$listed" 'all(.sessions[]; .running == true)' \
  "live tmux sessions should be marked as running"

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
missing=$($OMAMUX list)
assert_json "$missing" '(.sessions | length == 2)
    and .sessions[0].name == "alpha"
    and .sessions[0].favorite
    and (.sessions[0].running == false)
    and .sessions[1].name == "beta"
    and (.sessions[1].running == true)' \
  "missing favorites should remain visible in their saved order"
assert_json "$missing" '.sessions[0]
    | .windows == 0
      and .attachedClients == 0
      and .desktop == null
      and .nativeOrder == null' \
  "missing favorites should expose safe placeholder metadata"
$OMAMUX create alpha >/dev/null
restored=$($OMAMUX list)
assert_json "$restored" '.sessions[0].name == "alpha"
    and .sessions[0].favorite
    and (.sessions[0].running == true)' \
  "recreated sessions should recover their favorite position and running state"

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

state_file="$XDG_STATE_HOME/omamux/favorites.json"
head -c 262145 /dev/zero | tr '\0' x >"$state_file"
if state_overflow=$($OMAMUX list); then
  fail "state reads should reject byte overflow"
fi
assert_json "$state_overflow" '.ok == false and (.error | contains("262144-byte safety limit"))' \
  "state byte overflow should produce a bounded structured error"

jq -cn '{schemaVersion: 1, hosts: {local: {favorites: [
  range(0; 257) | {name: ("favorite-" + tostring), starredAt: 1}
]}}}' >"$state_file"
if state_rows=$($OMAMUX list); then
  fail "state reads should reject excess favorite rows"
fi
assert_json "$state_rows" '.ok == false and (.error | contains("safety limits"))' \
  "favorite row overflow should be rejected"

jq -cn --arg name "$(head -c 257 /dev/zero | tr '\0' x)" \
  '{schemaVersion: 1, hosts: {local: {favorites: [{name: $name, starredAt: 1}]}}}' \
  >"$state_file"
if state_field=$($OMAMUX list); then
  fail "state reads should reject oversized favorite names"
fi
assert_json "$state_field" '.ok == false and (.error | contains("safety limits"))' \
  "favorite field overflow should be rejected"

printf '{"schemaVersion":1,"hosts":{"local":{"favorites":[]}}}\n' >"$state_file"

for mode in session-bytes session-rows session-name client-bytes client-rows client-name; do
  if limited=$(OMAMUX_TMUX_SOCKET= OMAMUX_TMUX_BIN="$FAKE_TMUX" \
      OMAMUX_TEST_TMUX_MODE="$mode" $OMAMUX list); then
    fail "tmux list mode '$mode' should be rejected"
  fi
  assert_json "$limited" '.ok == false' \
    "tmux list mode '$mode' should return a structured error"
done

for mode in pane-bytes pane-rows window-name pane-title pane-command pane-path; do
  if limited=$(OMAMUX_TMUX_SOCKET= OMAMUX_TMUX_BIN="$FAKE_TMUX" \
      OMAMUX_TEST_TMUX_MODE="$mode" $OMAMUX detail alpha); then
    fail "tmux detail mode '$mode' should be rejected"
  fi
  assert_json "$limited" '.ok == false' \
    "tmux detail mode '$mode' should return a structured error"
done

for mode in bytes rows title; do
  if limited=$(OMAMUX_TEST_HYPR_MODE="$mode" $OMAMUX list); then
    fail "Hyprland client mode '$mode' should be rejected"
  fi
  assert_json "$limited" '.ok == false and (.error | contains("safety limits"))' \
    "Hyprland client mode '$mode' should return a bounded structured error"
done

printf '{not-json\n' >"$state_file"
if $OMAMUX list >/dev/null; then
  fail "malformed state should be reported rather than overwritten"
fi
grep -q '{not-json' "$state_file" \
  || fail "malformed state should be preserved"

printf 'PASS: omamux backend\n'
