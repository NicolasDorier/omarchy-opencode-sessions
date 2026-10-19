import type { Context, Definition } from "@opencode/plugin/tui"
import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises"
import { basename, join } from "node:path"

export type IndicatorState = "idle" | "busy" | "attention"

type StateEvent = {
  type: string
  status?: string
}

export function reduceIndicatorState(current: IndicatorState, event: StateEvent): IndicatorState {
  if (event.type === "permission.asked" || event.type === "form.created") return "attention"
  if (event.type === "permission.replied" || event.type === "form.replied" || event.type === "form.cancelled")
    return "busy"
  if (event.type === "session.execution.failed") return "attention"
  if (event.type === "session.execution.started" || event.type === "session.retry.scheduled") return "busy"
  if (event.type === "session.execution.succeeded" || event.type === "session.execution.interrupted") return "idle"
  if (event.type === "session.status") {
    if (event.status === "running" || event.status === "busy" || event.status === "retry") return "busy"
    if (event.status === "idle") return current === "attention" ? "attention" : "idle"
  }
  if (event.type === "session.idle") return current === "attention" ? "attention" : "idle"
  return current
}

function procStartTime(content: string): string {
  const closingParen = content.lastIndexOf(")")
  if (closingParen < 0) return ""
  return content.slice(closingParen + 1).trim().split(/\s+/)[19] || ""
}

function eventSessionID(event: any): string {
  return String(event?.data?.sessionID || event?.data?.form?.sessionID || "")
}

function eventStatus(event: any): string {
  return String(event?.data?.status?.type || event?.data?.status || "")
}

export async function setupSessionStatus(ctx: Context) {
  const runtimeDir = process.env.XDG_RUNTIME_DIR || "/tmp"
  const stateDir = join(runtimeDir, "omarchy-opencode-sessions")
  const statePath = join(stateDir, `${process.pid}.json`)
  const startTime = procStartTime(await readFile("/proc/self/stat", "utf8"))
  const initialDirectory = ctx.location?.directory || ctx.data.location.default().directory
  const states = new Map<string, IndicatorState>()

  let record = {
    version: 1,
    pid: process.pid,
    startTime,
    directory: initialDirectory,
    project: basename(initialDirectory) || initialDirectory,
    sessionID: "",
    title: "",
    state: "idle" as IndicatorState,
    stateChangedAt: Date.now(),
    updatedAt: Date.now(),
  }
  let writes = Promise.resolve()
  let lastSnapshot = ""

  async function writeRecord(force = false) {
    const comparable = JSON.stringify({ ...record, updatedAt: 0 })
    if (!force && comparable === lastSnapshot) return
    lastSnapshot = comparable
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

  async function refreshCurrent() {
    const route = ctx.ui.router.current()
    const sessionID = route.type === "session" ? route.sessionID : ""
    const info = sessionID ? ctx.data.session.get(sessionID) : undefined
    const tab = sessionID && ctx.ui.tabs.enabled()
      ? ctx.ui.tabs.list().find((candidate) => candidate.sessionID === sessionID)
      : undefined

    let state = sessionID ? states.get(sessionID) || "idle" : "idle"
    if (tab?.attention) state = "attention"
    else if (tab?.busy || (sessionID && ctx.data.session.status(sessionID) === "running")) state = "busy"
    else if (state !== "attention") state = "idle"
    if (sessionID) states.set(sessionID, state)

    const directory = info?.location?.directory || initialDirectory
    const changedState = record.sessionID !== sessionID || record.state !== state
    record = {
      ...record,
      directory,
      project: basename(directory) || directory,
      sessionID,
      title: String(info?.title || tab?.title || ""),
      state,
      stateChangedAt: changedState ? Date.now() : record.stateChangedAt,
    }
    await writeRecord()
  }

  await writeRecord(true)
  const stopListening = ctx.data.listen(({ details: event }) => {
    const sessionID = eventSessionID(event)
    if (sessionID) {
      states.set(sessionID, reduceIndicatorState(states.get(sessionID) || "idle", {
        type: event.type,
        status: eventStatus(event),
      }))
    }
    void refreshCurrent()
  })
  const timer = setInterval(() => void refreshCurrent(), 250)
  void refreshCurrent()

  return async () => {
    stopListening()
    clearInterval(timer)
    await writes
    await rm(statePath, { force: true })
  }
}

const OpenCodeSessionStatus = {
  id: "omarchy-session-status",
  setup: setupSessionStatus,
} satisfies Definition

export default OpenCodeSessionStatus
