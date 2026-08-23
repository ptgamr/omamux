# Omamux

Omamux is a local tmux session picker for the Omarchy Quattro bar. It brings flagship session picker from [TermRover.sh](https://termrover.sh/) to Omarchy.

Version `0.1.0` is intentionally local-only. Remote host support is planned after the local workflow is stable.

## Demo

https://github.com/user-attachments/assets/1808ea97-7fc0-4d30-8184-f7d6d5a5dbf4

The demo shows session navigation, favorites, reordering, and inline session renaming.

## Quick controls

- `j`/`k`: move the selection.
- `f`: toggle the selected session as a favorite.
- `J`/`K` (`Shift+j`/`Shift+k`): reorder a favorite.
- `r`: rename the selected session.
- `R` (`Shift+r`): refresh sessions.
- `C` (`Shift+c`): create a session.
- Right/Left: open session details or return to the session list.
- Enter: attach to the selection, focus its existing local window, or recreate a saved session that is not running.

## Features

- Lists local tmux sessions with window count, age, and attached client count.
- Opens an exact session in Omarchy's configured terminal.
- Focuses an existing local Hyprland terminal instead of opening a duplicate.
- Creates and immediately attaches to a named session.
- Renames an existing session while preserving its favorite position.
- Keeps ordered favorites, with drag and keyboard reordering.
- Preserves favorite sessions that no longer exist, shows them as `Not running`, and provides a one-click option to recreate them with the same name.
- Shows the windows and panes running inside each session.
- Supports mouse and keyboard navigation.
- Refreshes automatically without changing tmux configuration or global options.
- Inherits Quattro popup colors, borders, fonts, spacing, and theme changes.

## Requirements

- Omarchy Quattro
- tmux
- Bash
- jq

Omamux runs with your normal user permissions. It does not install packages or request elevated privileges.

## Install

```sh
omarchy plugin add https://github.com/ptgamr/omamux.git --enable
```

The manifest places Omamux in the right bar section by default. Move it if desired:

```sh
omarchy bar move io.github.ptgamr.omamux --section right
```

## Usage

- Left-click the bar widget to open or close the session panel.
- Right-click the bar widget to refresh.
- Use `j`/`k` or the arrow keys to select a session, then press Enter to attach.
- Click `☆`/`★`, or press `f`, to toggle a favorite.
- Drag a favorite row, or press `Shift+j`/`Shift+k`, to reorder it.
- Locally attached sessions show their Hyprland workspace as `ws N`.
- Press Right to inspect a session's window-and-pane tree and use `j`/`k` to select either level.
- Press Enter on a window or pane to focus that exact tmux target, then Left to go back.
- Click `+`, or press `Shift+C`, to create a session.
- Press `r` to rename the selected session, then Enter to confirm or Escape to cancel.
- Press `Shift+R`, use the refresh button in the panel header, or right-click the bar widget, to refresh.
- Press Escape to close.
- Missing favorites are labeled `Not running`; select one and press Enter or click `+` to recreate and attach to it.

New favorites are inserted at the top. Favorites for sessions that no longer exist remain visible in their saved order, where they can be reordered, removed, or recreated with the same name.

When a selected session is already attached in a local Hyprland terminal, Omamux switches to that window's workspace and focuses it. Remote-only attachments do not count as local windows. Selecting a different window or pane in a session with attached clients requires a second Enter because changing tmux's active target affects every client attached to that session.

## State

Favorite order is stored at:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/omamux/favorites.json
```

Writes are atomic. If the file is malformed, Omamux reports the problem and preserves the file rather than overwriting it.

## Develop

Validate the repository without installing it:

```sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml
node tests/test-model.mjs
bash tests/test-omamux.sh
```

The backend test creates a unique temporary tmux socket and state directory. It does not inspect or mutate your normal tmux server.

For live development, copy the repository contents into:

```text
~/.config/omarchy/plugins/io.github.ptgamr.omamux/
```

Then rescan and enable it:

```sh
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.ptgamr.omamux
```

QML changes in the user plugin directory reload automatically.

## Remove

```sh
omarchy plugin remove io.github.ptgamr.omamux
```

Removing the plugin does not remove its favorites file.

## Safety boundaries

Omamux does not edit `.tmux.conf`, Omarchy configuration, terminal configuration, tmux global/server options, colors, or theme synchronization. Session names are passed as command arguments rather than interpolated into shell command strings, and existing sessions are addressed with exact tmux targets.

See [PLAN.md](PLAN.md) for the full local-first design and the later remote-host direction.
