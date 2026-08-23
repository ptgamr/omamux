# Omamux

Omamux is a local tmux session picker for the Omarchy Quattro bar. It brings the session workflow from [TermRover](https://termrover.sh/) to the desktop while using Omarchy's native panel components and current theme.

Version `0.1.0` is intentionally local-only. Remote host support is planned after the local workflow is stable.

## Features

- Lists local tmux sessions with window count, age, and attached client count.
- Opens an exact session in Omarchy's configured terminal.
- Creates and immediately attaches to a named session.
- Keeps ordered favorites, with drag and keyboard reordering.
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
- Press Right to inspect a session's windows and panes, then Left to go back.
- Click `+`, or press `n`, to create a session.
- Press `r` to refresh and Escape to close.

New favorites are inserted at the top. Favorites for sessions that no longer exist remain saved but hidden; recreating the same session restores its previous favorite position.

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
