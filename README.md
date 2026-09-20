# Omarchy OpenCode Sessions

A compact, theme-aware Omarchy bar widget showing one status dot for every
running top-level OpenCode TUI.

## States

- **Idle**: outlined, dim dot
- **Busy**: filled accent dot, including automatic retries
- **Attention**: urgent filled dot with an outer ring for questions,
  permission requests, and blocking errors

Hover a dot to see its session title. Click it to focus the corresponding
terminal window in Hyprland. Child and subagent sessions are excluded.

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
