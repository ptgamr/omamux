# Omamux development plan

Date: 2026-08-24

## Goal

Build `omamux`, an Omarchy Quattro bar plugin that makes local tmux sessions easy to discover and resume. The first release targets only the local machine. Remote hosts are a later phase.

The interaction model is inspired by TermRover's session picker, while the visual treatment must use Omarchy's existing panel components and active theme tokens so it feels native beside plugins such as Agents and Network.

## Version 1 scope

### Bar widget

- Add one `bar-widget` with the permanent plugin ID `io.github.ptgamr.omamux`.
- Show a compact tmux glyph/label and the current session count.
- Left click toggles the session panel.
- Right click refreshes session data.
- Expose the normal Quattro `open`, `close`, `toggle`, and `refresh` lifecycle routes.

### Session panel

- Use Quattro's `Panel`, `KeyboardPanel`, `PanelKeyCatcher`, stock border surfaces, spacing scale, fonts, and active theme colors.
- Match existing Omarchy panels rather than copying TermRover's mobile colors literally.
- Show the local hostname, total session count, refresh action, and new-session action.
- Show one row per live tmux session with:
  - session name;
  - window count;
  - age;
  - attached client count;
  - green status when available and amber when attached;
  - favorite star;
  - attach affordance.
- Put favorites first in their saved order. Keep non-favorites in tmux's returned order.
- Insert newly starred sessions at the top of the favorite block, matching TermRover.
- Reorder favorite sessions with drag-and-drop, with keyboard-accessible move controls as a fallback.
- Clicking a row opens a new Omarchy terminal attached to that exact session.
- Provide an inline new-session form with a suggested name (`main`, then `main-2`, and so on).
- Reject empty names and names containing `.` or `:`, then create and attach the session.
- Support Escape to close, Up/Down to move selection, Enter to attach, `n` to create, `r` to refresh, and `f` to toggle the selected favorite.
- Refresh when opened, after mutations, and periodically while visible.

### Empty and error states

- No tmux server: show a friendly empty state and the create action.
- tmux not installed: show a clear dependency message without attempting privileged installation.
- Command failure or malformed data: keep the panel usable and show a concise error with a retry action.
- A favorite whose session no longer exists remains in state but is hidden; recreating the same session name restores its favorite position.

## Architecture

```text
manifest.json
    |
    v
BarWidget.qml ---- loads ----> Panel.qml
                                 |
                                 v
                              Model.js
                                 |
                                 v
                         scripts/omamux
                                 |
                     +-----------+-----------+
                     |                       |
                   tmux              favorites.json
```

Planned repository layout:

```text
omamux/
├── manifest.json
├── BarWidget.qml
├── Panel.qml
├── Model.js
├── scripts/
│   └── omamux
├── tests/
│   └── test-omamux.sh
├── README.md
├── LICENSE
└── PLAN.md
```

### QML responsibilities

- `BarWidget.qml` owns the bar presentation, panel loader, injected bar/settings state, IPC lifecycle, and lightweight session count.
- `Panel.qml` owns interaction state, keyboard navigation, list rendering, create mode, and backend process lifecycle.
- `Model.js` contains pure parsing, sorting, age formatting, name validation, and suggested-name helpers so these rules can be tested separately from the shell.

### Backend responsibilities

`scripts/omamux` will be a small local-only command API:

```text
omamux list
omamux attach <session-name>
omamux create <session-name>
omamux favorite toggle <session-name>
omamux favorite reorder <session-name>...
```

- All machine-readable output is JSON.
- Commands are passed as argument arrays; session names are never interpolated into shell command strings.
- Existing sessions are addressed with exact tmux targets (`=<name>`) to avoid prefix matches.
- `list` uses `session_name`, `session_windows`, `session_created`, and `session_attached` from tmux.
- Attach/create launches through `omarchy launch terminal`/`omarchy-launch-terminal`, preserving Omarchy's configured terminal.
- The backend does not rename, kill, detach, or otherwise mutate an existing session in version 1.

### Persistent state

- Store state under `${XDG_STATE_HOME:-$HOME/.local/state}/omamux/favorites.json`.
- Use an ordered JSON list, because list order is the display order.
- Include a schema version and a `local` host key now, so adding remote host identities later does not require replacing the format.
- Write changes atomically and never overwrite malformed state silently.

Example shape:

```json
{
  "schemaVersion": 1,
  "hosts": {
    "local": {
      "favorites": [
        { "name": "sportdb", "starredAt": 1787486761000 }
      ]
    }
  }
}
```

## Safety boundaries

- The plugin runs unprivileged as the current user.
- It will not edit `~/.tmux.conf`, Omarchy config, terminal config, or files under `/usr/share/omarchy`.
- It will not change tmux global/server options, colors, OSC values, or theme synchronization. Those settings affect every client on a shared tmux server and are outside Omamux's session-management scope.
- No remote commands, SSH credentials, host definitions, or network access are part of version 1.
- Dependencies will be limited to tools already expected on Omarchy: tmux, jq, Bash, Quickshell, and the Omarchy terminal launcher. They will be documented explicitly.

## Implementation phases

### 1. Plugin contract and backend

- Create the final namespaced manifest and repository structure.
- Implement list, exact attach, create, favorite toggle, and favorite reorder commands.
- Add atomic state persistence and structured errors.
- Test against an isolated tmux server/socket so development does not touch the user's real sessions.

### 2. Native Omarchy UI

- Implement the bar widget and lifecycle forwarding.
- Build the panel from installed Quattro components and theme tokens.
- Add session cards, empty/error states, favorite controls, creation flow, keyboard navigation, and timed refresh.
- Keep the size and information density consistent with the existing Agents and Network panels.

### 3. Local integration and polish

- Validate the plugin folder and lint all QML.
- Install/sync a development copy under `~/.config/omarchy/plugins/io.github.ptgamr.omamux` only after explicit approval.
- Test click, Escape, keyboard navigation, favorite persistence/reordering, creation, attach, refresh, disable/re-enable, shell restart, and theme switching.
- Capture a screenshot and compare spacing, borders, typography, colors, and panel anchoring with the supplied Omarchy references.

### 4. Documentation and release readiness

- Document install, enable, placement, usage, dependencies, state location, removal, and troubleshooting.
- Add the MIT license and optional marketplace preview image.
- Validate the final repository with the same checks used by Omarchy's plugin installer.

## Validation checklist

Automated:

```sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml
bash tests/test-omamux.sh
```

Runtime:

```sh
omarchy-shell shell rescanPlugins
omarchy plugin list --json
omarchy-shell shell summon io.github.ptgamr.omamux '{}'
omarchy-shell shell hide io.github.ptgamr.omamux
```

Acceptance criteria:

- The plugin validates with no manifest or QML errors.
- The panel visually belongs with stock Quattro panels in both light and dark themes.
- Session counts and metadata match direct tmux output.
- Attach and create work with spaces and shell metacharacters in valid session names without command injection.
- Favorites survive shell restart; newly starred sessions move to the top; reordering persists.
- No test or plugin action changes unrelated tmux sessions or global tmux/Omarchy configuration.

## Later: remote hosts

Remote support will be a separate phase after the local workflow is stable. It will add a host/provider layer above the existing backend contract, host-scoped favorite lists, explicit SSH execution, connection/error state, and a host selector. The local provider will remain the default and will not require SSH.

Remote work is deliberately excluded from version 1 so authentication, host-key verification, latency, terminal launching, and remote tmux discovery can be designed and tested as one coherent feature rather than hidden inside the local implementation.
