# Architecture and Troubleshooting

OpenCode Sessions joins two plugin systems. A global OpenCode hook observes
session events and writes transient state. An Omarchy bar widget discovers
those records, maps each process to its Hyprland window, and renders the dots.

## Components

| Component | Path | Responsibility |
|---|---|---|
| OpenCode hook | `opencode/omarchy-session-status.ts` | Convert OpenCode events into one state record per TUI process |
| Session scanner | `scripts/session-scan` | Remove stale records and map OpenCode process ancestry to Hyprland clients |
| Bar widget | `BarWidget.qml` | Poll the scanner, render dots and tooltips, and focus clicked sessions |
| Hook installer | `scripts/install-opencode-hook` | Link the bundled hook into the global OpenCode plugin directory |
| Hook uninstaller | `scripts/uninstall-opencode-hook` | Remove the managed hook link and transient records |

The hook is installed at:

```text
~/.config/opencode/plugins/omarchy-session-status.ts
```

OpenCode automatically loads JavaScript and TypeScript files from that
directory. It reads plugins only at startup or configuration reload.

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

The global hook also loads for commands such as `opencode run`, `opencode db`,
and `opencode debug`. Those commands must not become bar sessions. The hook
reads `/proc/self/cmdline` and creates a record only for the default interactive
TUI invocation.

Child and delegated-agent sessions run inside the same OpenCode process. The
hook records `session.created` and `session.updated` metadata and ignores any
session with `parentID`. Therefore, subagents do not receive separate dots or
overwrite their parent TUI's state.

## State Model

The bar exposes three states:

| State | Appearance | Meaning |
|---|---|---|
| Idle | Outlined dim dot | The TUI is waiting for another prompt |
| Busy | Filled accent dot | OpenCode is generating, executing tools, or waiting to retry automatically |
| Attention | Urgent filled dot with an outer ring | OpenCode cannot continue without user attention |

Transitions:

| Event | Result |
|---|---|
| `session.status: busy` | Busy |
| `session.status: retry` | Busy |
| `session.status: idle` | Idle, unless Attention is sticky |
| `session.idle` | Idle, unless Attention is sticky |
| `question.asked` | Attention |
| `permission.asked` | Attention |
| Question or permission reply | Busy |
| Blocking `session.error` | Attention |
| `MessageAbortedError` | Idle |
| Completed assistant message with final finish reason | Idle |
| Completed assistant message with `tool-calls` | No change |

Attention caused by an error remains sticky across idle events. It clears when
the session becomes Busy again. This prevents a trailing idle event from hiding
an error that still needs inspection.

### Idle Fallback

OpenCode 1.18 does not consistently deliver `session.idle` to global plugins.
The reliable fallback is `message.updated` for an assistant message whose
`time.completed` exists and whose finish reason is final. Intermediate
assistant messages finish with `tool-calls`; treating those as Idle would make
the dot flicker while tools are still running, so they are ignored. `unknown`
and `error` finish reasons are also not treated as successful completion.

## Avoiding Startup Deadlocks

Plugin initialization must not call `client.session.list()` or another API on
the same OpenCode server. The plugin is initialized while that server is still
bootstrapping; awaiting a request back into it can deadlock startup and prevent
OpenCode from opening.

The hook therefore writes an initial Idle record without querying the API. It
learns session IDs and titles from subsequent events. Until then, the scanner
uses the terminal title as a display fallback.

## Window Discovery

The hook records the OpenCode PID, not a terminal-specific identifier. On every
scan, `session-scan` obtains `hyprctl clients -j`, walks each OpenCode process's
parent chain through `/proc`, and selects the first ancestor represented by a
Hyprland client. This supports Foot and other terminals without matching a
terminal class.

Dots are sorted by process start time, producing stable oldest-to-newest order.
The terminal title replaces the stored session title when it begins with
`OC | `, ensuring that switching sessions within a TUI updates the title-only
tooltip even without a server event for the route change.

## Window Focus

Current Omarchy versions route `hyprctl dispatch` through the Hyprland Lua API.
The legacy command below fails with a Lua parse error:

```text
hyprctl dispatch focuswindow address:0x123
```

The widget instead executes the equivalent Lua dispatcher expression:

```lua
hl.dsp.focus({ window = "address:0x123" })
```

This focuses the exact client and switches to its normal or special workspace.
The address is shell-quoted with Omarchy's `Util.shellQuote`.

## Reload Behavior

Different changes require different reloads:

| Changed component | Required action |
|---|---|
| QML, manifest, or bar configuration | `omarchy restart shell` |
| OpenCode hook | Restart each TUI, or send it `SIGUSR2` |
| Hook symlink installation | Restart each running TUI once |

`SIGUSR2` is OpenCode's supported configuration reload path. The TUI forwards
it to its worker, which reloads plugins without requiring the terminal window
to be recreated.

## Troubleshooting

### OpenCode no longer starts

Remove the hook link to isolate the integration:

```bash
rm ~/.config/opencode/plugins/omarchy-session-status.ts
```

Then test the hook without installing it globally:

```bash
OPENCODE_CONFIG_CONTENT='{
  "plugin": [
    "file:///absolute/path/to/opencode/omarchy-session-status.ts"
  ]
}' timeout 15 opencode debug config
```

The command must print the resolved configuration and exit. A hang during
plugin loading usually indicates a startup-time API self-call.

### Dot remains Busy after completion

Inspect the record and the latest assistant message:

```bash
jq . "$XDG_RUNTIME_DIR"/omarchy-opencode-sessions/*.json
opencode db --format json 'SELECT session_id, data FROM message ORDER BY time_created DESC LIMIT 5'
```

If the final assistant message has `time.completed` and `finish: "stop"` but
the record remains Busy, verify that the TUI loaded the current hook and reload
it with `SIGUSR2` or restart it.

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
