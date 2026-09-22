#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/state" "$tmp/proc/100" "$tmp/proc/101"

write_stat() {
  local pid="$1" name="$2" ppid="$3" start="$4"
  printf '%s (%s) S %s 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 %s 0\n' \
    "$pid" "$name" "$ppid" "$start" > "$tmp/proc/$pid/stat"
}

write_stat 100 opencode 101 200
write_stat 101 terminal 1 100

cat > "$tmp/state/100.json" <<'JSON'
{"version":1,"pid":100,"startTime":"200","project":"repo","title":"Stored title","state":"attention","stateChangedAt":300}
JSON
cat > "$tmp/state/999.json" <<'JSON'
{"version":1,"pid":999,"startTime":"1","project":"stale","title":"Stale","state":"idle"}
JSON

cat > "$tmp/hyprctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '[{"pid":101,"address":"0xabc","title":"OC | Live title"}]'
SH
chmod +x "$tmp/hyprctl"

result="$(
  OPENCODE_SESSIONS_STATE_DIR="$tmp/state" \
  OPENCODE_SESSIONS_PROC_ROOT="$tmp/proc" \
  OPENCODE_SESSIONS_HYPRCTL="$tmp/hyprctl" \
  "$root/scripts/session-scan"
)"

jq -e 'length == 1' <<< "$result" >/dev/null
jq -e '.[0] == {pid:100,startTime:"200",project:"repo",title:"Live title",state:"attention",stateChangedAt:300,address:"0xabc"}' \
  <<< "$result" >/dev/null
[[ ! -e "$tmp/state/999.json" ]]

printf 'session-scan tests passed\n'
