import type { Plugin } from "@opencode-ai/plugin"
import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises"
import { basename, join } from "node:path"

export type IndicatorState = "idle" | "busy" | "attention"

type StateEvent = {
  type: string
  status?: string
  errorName?: string
  role?: string
  finish?: string
  completed?: boolean
}

export function reduceIndicatorState(current: IndicatorState, event: StateEvent): IndicatorState {
  if (event.type === "question.asked" || event.type === "permission.asked") return "attention"
  if (event.type === "question.replied" || event.type === "question.rejected" || event.type === "permission.replied")
    return "busy"
  if (event.type === "session.error") return event.errorName === "MessageAbortedError" ? "idle" : "attention"
  if (event.type === "message.updated" && event.role === "assistant" && event.completed) {
    if (event.finish && !["tool-calls", "unknown", "error"].includes(event.finish)) return "idle"
  }
  if (event.type === "session.status") {
    if (event.status === "busy" || event.status === "retry") return "busy"
    if (event.status === "idle") return current === "attention" ? "attention" : "idle"
  }
  if (event.type === "session.idle") return current === "attention" ? "attention" : "idle"
  return current
}

const NON_TUI_COMMANDS = new Set([
  "completion", "acp", "mcp", "attach", "run", "debug", "providers", "agent",
  "upgrade", "uninstall", "serve", "web", "models", "stats", "export", "import",
  "github", "session", "plugin", "db",
])

export function isInteractiveTui(argv: string[]): boolean {
  const args = argv.slice(1)
  return !args.some((arg) => NON_TUI_COMMANDS.has(arg))
}

function procStartTime(content: string): string {
  const closingParen = content.lastIndexOf(")")
  if (closingParen < 0) return ""
  return content.slice(closingParen + 1).trim().split(/\s+/)[19] || ""
}

function eventSessionID(event: any): string {
  return String(event?.properties?.sessionID || event?.properties?.info?.sessionID || event?.properties?.info?.id || "")
}

const OpenCodeSessionStatus = (async ({ directory }) => {
  const commandLine = (await readFile("/proc/self/cmdline", "utf8")).split("\0").filter(Boolean)
  if (!isInteractiveTui(commandLine)) return {}

  const runtimeDir = process.env.XDG_RUNTIME_DIR || "/tmp"
  const stateDir = join(runtimeDir, "omarchy-opencode-sessions")
  const statePath = join(stateDir, `${process.pid}.json`)
  const startTime = procStartTime(await readFile("/proc/self/stat", "utf8"))
  const topLevelSessions = new Map<string, any>()

  let record = {
    version: 1,
    pid: process.pid,
    startTime,
    directory,
    project: basename(directory) || directory,
    sessionID: "",
    title: "",
    state: "idle" as IndicatorState,
    stateChangedAt: Date.now(),
    updatedAt: Date.now(),
  }
  let writes = Promise.resolve()

  async function writeRecord() {
    record.updatedAt = Date.now()
    const snapshot = JSON.stringify(record) + "\n"
    writes = writes.then(async () => {
      await mkdir(stateDir, { recursive: true, mode: 0o700 })
      const temporary = `${statePath}.${process.pid}.${Date.now()}.tmp`
      await writeFile(temporary, snapshot, { mode: 0o600 })
      await rename(temporary, statePath)
    }).catch(() => {})
    await writes
  }

  function sessionInfo(sessionID: string, supplied?: any): any | null {
    if (supplied) {
      if (supplied.parentID) {
        topLevelSessions.set(sessionID, null)
        return null
      }
      topLevelSessions.set(sessionID, supplied)
      return supplied
    }
    return topLevelSessions.get(sessionID) || null
  }

  await writeRecord()

  return {
    event: async ({ event }: any) => {
      const sessionID = eventSessionID(event)
      if (!sessionID) return

      const supplied = event.type === "session.created" || event.type === "session.updated"
        ? event?.properties?.info
        : undefined
      const info = sessionInfo(sessionID, supplied)
      if (!info || (info.directory && info.directory !== directory)) return

      record.sessionID = sessionID
      record.title = String(info.title || record.title || "")
      const nextState = reduceIndicatorState(record.state, {
        type: String(event.type || ""),
        status: String(event?.properties?.status?.type || ""),
        errorName: String(event?.properties?.error?.name || ""),
        role: String(event?.properties?.info?.role || ""),
        finish: String(event?.properties?.info?.finish || ""),
        completed: Number(event?.properties?.info?.time?.completed || 0) > 0,
      })
      if (nextState !== record.state) record.stateChangedAt = Date.now()
      record.state = nextState
      await writeRecord()
    },
    dispose: async () => {
      await writes
      await rm(statePath, { force: true })
    },
  }
}) satisfies Plugin

export default OpenCodeSessionStatus
