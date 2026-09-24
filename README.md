# Omarchy OpenCode Sessions

A compact, theme-aware Omarchy bar widget showing one status dot for every
running top-level OpenCode TUI.

## States

- **Idle**: outlined, dim dot
- **Busy**: filled accent dot, including automatic retries
- **Attention**: urgent filled dot with an outer ring for questions,
  permission requests, and blocking errors

Hover a dot to see its session title, or click it to focus that session. The
searchable session menu is available over IPC and sorts by the most recent
state change. Enter focuses the first filtered session; clicking a row focuses
that session directly. Child and subagent sessions are excluded.

An optional Hyprland binding opens the menu directly:

```lua
o.bind("SUPER + A", "OpenCode sessions", "omarchy-shell nicolasdorier.opencode-sessions toggle")
```

Session activation uses `_G.omarchy_focus_window(window)` when that optional
Hyprland Lua hook exists, falling back to direct window focus otherwise. The
hook can restore application-specific hidden windows before focusing them.

## Requirements

- Omarchy with the Quickshell bar plugin system
- OpenCode 1.18 or newer
- Hyprland, `jq`, and standard Linux `/proc`

## Install

```bash
omarchy plugin add https://github.com/nicolasdorier/omarchy-opencode-sessions.git --enable
~/.config/omarchy/plugins/nicolasdorier.opencode-sessions/scripts/install-opencode-hook
omarchy bar move nicolasdorier.opencode-sessions --before omarchy.agents
```

Restart every running OpenCode TUI once after installing the hook. New sessions
load it automatically. The hook writes transient, per-process JSON records to
`$XDG_RUNTIME_DIR/omarchy-opencode-sessions/`; no session content is persisted.

## Uninstall

```bash
~/.config/omarchy/plugins/nicolasdorier.opencode-sessions/scripts/uninstall-opencode-hook
omarchy plugin remove nicolasdorier.opencode-sessions
```

## Test

```bash
./tests/run
```

See [docs/architecture.md](docs/architecture.md) for the integration design,
state transitions, runtime record format, reload behavior, and troubleshooting.

## License

MIT
