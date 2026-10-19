# Architecture and Troubleshooting

OpenCode Sessions joins two plugin systems. An OpenCode CLI plugin observes
the active TUI route and session events and writes transient state. An Omarchy
bar widget discovers those records, maps each process to its Hyprland window,
and renders the dots.

## Components

| Component | Path | Responsibility |
|---|---|---|
| OpenCode CLI plugin | `opencode/omarchy-session-status.ts` | Convert OpenCode events into one state record per TUI process |
| Session scanner | `scripts/session-scan` | Remove stale records and map OpenCode process ancestry to Hyprland clients |
| Bar widget | `BarWidget.qml` | Poll the scanner, render dots and tooltips, and focus clicked sessions |
| Plugin installer | `scripts/install-opencode-hook` | Link and enable the bundled plugin in OpenCode CLI settings |
| Plugin uninstaller | `scripts/uninstall-opencode-hook` | Disable the managed plugin and remove transient records |

The CLI plugin is installed at:

```text
~/.config/opencode/cli-plugins/omarchy-session-status/
```

The installer adds that path to the `plugins` array in
`~/.config/opencode/cli.json`. OpenCode reads CLI plugins at TUI startup.

## Runtime Records

Each interactive OpenCode TUI writes:

```text
$XDG_RUNTIME_DIR/omarchy-opencode-sessions/<pid>.json
```

Example:

```json
{
  "version": 1,
  "pid": 1234,
  "startTime": "29741996",
  "directory": "/home/user/src/project",
  "project": "project",
  "sessionID": "ses_example",
  "title": "Review pull request",
  "state": "busy",
  "stateChangedAt": 1789899498000,
  "updatedAt": 1789899498379
}
```

Writes use a temporary file followed by an atomic rename, so the one-second
scanner cannot observe partial JSON. Files use mode `0600`; the containing
directory uses mode `0700`.

The Linux process start time from `/proc/<pid>/stat` accompanies the PID. The
scanner compares both values before accepting a record, preventing PID reuse
from associating an old record with an unrelated process. Dead-process and
start-time-mismatch records are deleted automatically.

## TUI Filtering

The plugin is registered as a CLI plugin, so server commands such as
`opencode run`, `opencode db`, and `opencode debug` do not create bar sessions.

Child and delegated-agent sessions run inside the same OpenCode process. The
plugin follows only the session route currently selected by that TUI. Therefore,
subagents do not receive separate dots or overwrite their parent TUI's state.

## State Model

The bar exposes three states:

| State | Appearance | Meaning |
|---|---|---|
| Idle | Dim outlined circle | The TUI is waiting for another prompt |
| Busy | Rotating accent spinner | OpenCode is generating, executing tools, or waiting to retry automatically |
| Attention | Urgent exclamation circle | OpenCode cannot continue without user attention |

Transitions:

| Event | Result |
|---|---|
| `session.status: running` | Busy |
| `session.status: retry` | Busy |
| `session.status: idle` | Idle, unless Attention is sticky |
| `session.idle` | Idle, unless Attention is sticky |
| `form.created` | Attention |
| `permission.asked` | Attention |
| Form or permission reply | Busy |
| `session.execution.failed` | Attention |
| `session.execution.interrupted` | Idle |
| `session.execution.succeeded` | Idle |

Attention caused by an error remains sticky across idle events. It clears when
the session becomes Busy again. This prevents a trailing idle event from hiding
an error that still needs inspection.

The CLI plugin also checks OpenCode's client-side session and tab status. This
keeps the record synchronized when switching routes and covers status changes
that occur between individual events.

## Window Discovery

The hook records the OpenCode PID, not a terminal-specific identifier. On every
scan, `session-scan` obtains `hyprctl clients -j`, walks each OpenCode process's
parent chain through `/proc`, and selects the first ancestor represented by a
Hyprland client. This supports Foot and other terminals without matching a
terminal class.

The popup sorts sessions by `stateChangedAt` descending, so the session whose
status changed most recently appears first. `updatedAt` remains a record-write
timestamp and does not affect ordering.

The terminal title replaces the stored session title when it begins with
`OC | `, ensuring that switching sessions within a TUI updates the title-only
tooltip even without a server event for the route change.

## Session Menu

The `nicolasdorier.opencode-sessions` IPC target opens a centered, full-screen
menu surface matching the native `omarchy menu select` interface: menu-theme
card, dimmed scrim, inline type-to-filter header, and highlighted rows. A
Hyprland shortcut can call it with:

```bash
omarchy-shell nicolasdorier.opencode-sessions toggle
```

Clicking a bar icon continues to focus that session directly. The popup lists
session titles with the same state indicators used by the bar.

The menu surface owns keyboard focus. The first filtered session is highlighted
initially. Typing filters titles case-insensitively, the arrow keys move the
highlighted row, Escape clears the filter or closes the menu, and Enter
activates the highlighted session. Clicking a row activates that specific
session without changing the keyboard selection. Before focusing the selected
window, activation focuses the popup's `omarchy-opencode-sessions-menu` layer
namespace. This keeps focus handoff deterministic while the popup closes.

## Window Focus

Current Omarchy versions route `hyprctl dispatch` through the Hyprland Lua API.
The legacy command below fails with a Lua parse error:

```text
hyprctl dispatch focuswindow address:0x123
```

The widget resolves the exact client and uses an optional global focus hook:

```lua
local window = hl.get_window("address:0x123")
local focus = rawget(_G, "omarchy_focus_window")
if focus and window then
    focus(window)
else
    hl.dispatch(hl.dsp.focus({ window = "address:0x123" }))
end
```

The hook lets local Hyprland configuration restore a hidden window before it is
focused. Without one, the widget focuses the client directly and switches to
its normal or special workspace. The action is shell-quoted with Omarchy's
`Util.shellQuote`.

## Reload Behavior

Different changes require different reloads:

| Changed component | Required action |
|---|---|
| QML, manifest, or bar configuration | `omarchy restart shell` |
| OpenCode CLI plugin | Restart each TUI |
| Plugin symlink or settings installation | Restart each running TUI once |

Restart the TUI to guarantee that CLI plugin code changes take effect.

## Troubleshooting

### OpenCode no longer starts

Remove the hook link to isolate the integration:

```bash
~/.config/omarchy/plugins/nicolasdorier.opencode-sessions/scripts/uninstall-opencode-hook
```

Then restart OpenCode. Run the installer again to restore the plugin.

### Dot remains Busy after completion

Inspect the record and the latest assistant message:

```bash
jq . "$XDG_RUNTIME_DIR"/omarchy-opencode-sessions/*.json
opencode db --format json 'SELECT session_id, data FROM message ORDER BY time_created DESC LIMIT 5'
```

If the final assistant message has `time.completed` and `finish: "stop"` but
the record remains Busy, verify that the TUI loaded the current hook and restart
it. Records written by the current hook include `stateChangedAt`.

### Clicking does not focus the session

Run the scanner and inspect the reported address:

```bash
~/.config/omarchy/plugins/nicolasdorier.opencode-sessions/scripts/session-scan
hyprctl clients -j
```

Test focus using the Lua dispatcher syntax, replacing the address:

```bash
hyprctl dispatch 'hl.dsp.focus({ window = "address:0x123" })'
```

### Widget does not update after a QML change

Restart the shell explicitly:

```bash
omarchy restart shell
```

Although user plugin files are watched, an explicit restart is the dependable
way to ensure the running QML instance has been replaced.

## Verification

Run all automated checks from the repository root:

```bash
./tests/run
```

The suite covers state transitions, final-message Idle fallback, manual aborts,
runtime record creation and disposal, stale PID cleanup, process ancestry,
terminal-title selection, scanner JSON, shell scripts, and manifest validity.
QML can be checked separately with:

```bash
qmllint -I /usr/share/omarchy/shell BarWidget.qml
```
