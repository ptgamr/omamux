# Omamux Agent Guide

## Scope

These instructions apply to the entire repository.

Omamux is a local-first tmux session manager implemented as an Omarchy Quattro
`bar-widget`. Keep changes focused on the local host until remote-host support is
explicitly requested.

## Repository map

- `manifest.json`: Omarchy plugin contract and bar-widget defaults.
- `BarWidget.qml`: tray widget, polling, backend process, and panel loader.
- `Panel.qml`: session list, details tree, keyboard/mouse interaction, and animations.
- `OmamuxIcon.qml`: shared tray and panel icon.
- `Model.js`: pure parsing, formatting, selection, and reorder helpers.
- `scripts/omamux`: Bash backend; all tmux, Hyprland, and persisted-state access belongs here.
- `tests/test-model.mjs`: pure JavaScript model tests.
- `tests/test-omamux.sh`: isolated backend integration tests.

## Behavioral and safety invariants

- Do not edit `.tmux.conf`, Omarchy configuration, terminal configuration, or tmux
  server/global options.
- Address sessions, windows, and panes with exact tmux targets. Do not interpolate
  session names into shell command strings.
- Keep backend stdout machine-readable JSON. Diagnostics and subprocess output must
  never corrupt the JSON response.
- Preserve malformed state files instead of overwriting them. State writes must remain
  atomic.
- Favorite order persists at
  `${XDG_STATE_HOME:-$HOME/.local/state}/omamux/favorites.json`.
- A favorite whose tmux session no longer exists remains visible as a saved,
  `running: false` placeholder and can be recreated with the same name.
- Never kill or modify a user's real tmux session during development or testing.
- Reuse Omarchy's `qs.Ui` and `qs.Commons` components and current theme values. Keep
  the panel compact and visually aligned with built-in Omarchy panels.
- Never launch a second Quickshell process. Omamux must run inside the existing,
  long-running Omarchy shell.

## Change workflow

1. Inspect `git status` before editing and preserve unrelated user changes.
2. Keep data collection and mutations in `scripts/omamux`; keep reusable deterministic
   logic in `Model.js`; keep rendering and interaction in QML.
3. Update tests whenever the backend JSON contract or model behavior changes.
4. Update README feature and usage documentation for user-visible behavior.
5. Do not commit, push, publish, or replace `preview.png` unless the user asks.

## Required validation

Run these from the repository root:

```sh
bash -n scripts/omamux tests/test-omamux.sh
git diff --check
node tests/test-model.mjs
bash tests/test-omamux.sh
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml
omarchy plugin validate .
```

`tests/test-omamux.sh` creates a unique temporary tmux socket and state directory. It
must not inspect or mutate the normal tmux server. In a restricted agent sandbox, its
Unix socket may require running the test with normal host access.

Treat warnings or failures as real until their cause is understood. Do not claim the
UI works merely because `qmllint` passes.

## Live UI testing

UI changes must be tested in the running Omarchy shell when a graphical session is
available.

### 1. Sync the development files

Use the installed plugin directory, never `/usr/share/omarchy/shell`:

```sh
PLUGIN_ID=io.github.ptgamr.omamux
PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"

mkdir -p "$PLUGIN_DIR/scripts"
cp manifest.json BarWidget.qml Panel.qml Model.js OmamuxIcon.qml "$PLUGIN_DIR/"
cp scripts/omamux "$PLUGIN_DIR/scripts/omamux"
chmod +x "$PLUGIN_DIR/scripts/omamux"
```

This makes the installed checkout a disposable development copy. Do not commit changes
from inside it. A normal GitHub installation can be restored afterward with
`omarchy plugin remove` followed by `omarchy plugin add`.

### 2. Reload and open Omamux

```sh
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.ptgamr.omamux
omarchy-shell shell summon io.github.ptgamr.omamux '{}'
```

Saving files under the user plugin directory normally reloads QML automatically. If
the backend payload reflects new fields but the visible panel still has old labels,
icons, counts, or actions, the old bar-widget instance is stale. Perform the documented
full shell restart, wait for the shell to answer, and open Omamux again:

```sh
omarchy-restart-shell
omarchy-shell shell ping
omarchy-shell shell summon io.github.ptgamr.omamux '{}'
```

Inspect shell errors when the panel does not load or behaves unexpectedly:

```sh
qs log -p "$OMARCHY_PATH/shell" --tail 100
```

Do not treat unrelated desktop-entry warnings as Omamux failures. Look for paths under
`io.github.ptgamr.omamux` and concrete QML errors.

### 3. Check the backend payload first

Before diagnosing rendering, verify the installed backend returns the expected data:

```sh
"$PLUGIN_DIR/scripts/omamux" list | jq .
```

For a missing favorite, verify `favorite` is `true`, `running` is `false`, and the
placeholder has zero windows/clients plus null desktop/native-order metadata. If that
payload is correct but the row still shows `age unknown`, a yellow dot, or a details
chevron, the QML instance is stale and needs the full shell restart above.

### 4. Visual and interaction checklist

Verify all relevant states, not only the changed row:

- The tray icon matches the size and baseline of neighboring Omarchy icons.
- The panel is anchored to the right screen edge and uses built-in spacing, colors,
  borders, and typography.
- The header distinguishes running sessions from saved missing favorites.
- Attached sessions use the blue status dot; unattached sessions use yellow; missing
  favorites use the muted color.
- Missing favorites show `Not running · favorite saved`, retain their star/order, show
  a `+` action instead of the details chevron, and recreate from either `+` or Enter.
- Opening the panel and pressing `j` or Down first selects the first row, not the second.
- `j`/`k` moves selection; `J`/`K` reorders favorites with a smooth swap animation.
- `f` toggles favorites; `r` renames; `R` refreshes; `C` creates a session.
- Right opens the window/pane hierarchy for a running session; Left returns.
- Enter on a running session attaches or focuses its existing local Hyprland window.
- Window selection targets the chosen tmux window/pane without highlighting pane rows
  as active windows.
- Drag reordering displaces surrounding rows continuously and does not flicker icons or
  row backgrounds.
- Escape and shell hide/close routes dismiss the panel cleanly.

When useful, capture the open panel with `grim` into `/tmp` and inspect that image. Do
not add diagnostic screenshots or recordings to the repository.

### 5. Safe missing-favorite scenario

Only when the user has authorized live UI testing, use a dedicated name such as
`omamux-ui-test`. First confirm that neither a live session nor a saved placeholder with
that name already exists. Abort rather than touching it if it was not created by the
current test.

1. Create the disposable session with `tmux new-session -d -s omamux-ui-test`.
2. Favorite it through the installed backend.
3. Kill only `=omamux-ui-test`; never run `tmux kill-server`.
4. Refresh the panel and verify the missing placeholder state described above.
5. Press Enter or click `+`; verify the same name is recreated, remains favorite, and
   opens or focuses its terminal.
6. Cleanup only the disposable session. Remove its favorite through the backend if it
   is still saved, then kill that exact session if it is still running.

After UI testing, rerun the required validation commands and inspect `git status` so
runtime copies, screenshots, state files, or test artifacts are not accidentally
committed.
