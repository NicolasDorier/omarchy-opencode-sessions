import assert from "node:assert/strict"
import { mkdtemp, readFile, stat } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import OpenCodeSessionStatus, { reduceIndicatorState, setupSessionStatus } from "../opencode/omarchy-session-status.ts"

assert.equal(OpenCodeSessionStatus.id, "omarchy-session-status")
assert.equal(reduceIndicatorState("idle", { type: "session.status", status: "running" }), "busy")
assert.equal(reduceIndicatorState("idle", { type: "session.status", status: "retry" }), "busy")
assert.equal(reduceIndicatorState("busy", { type: "session.idle" }), "idle")
assert.equal(reduceIndicatorState("busy", { type: "form.created" }), "attention")
assert.equal(reduceIndicatorState("busy", { type: "permission.asked" }), "attention")
assert.equal(reduceIndicatorState("attention", { type: "session.idle" }), "attention")
assert.equal(reduceIndicatorState("attention", { type: "session.status", status: "idle" }), "attention")
assert.equal(reduceIndicatorState("attention", { type: "form.replied" }), "busy")
assert.equal(reduceIndicatorState("attention", { type: "permission.replied" }), "busy")
assert.equal(reduceIndicatorState("busy", { type: "session.execution.failed" }), "attention")
assert.equal(reduceIndicatorState("busy", { type: "session.execution.interrupted" }), "idle")
assert.equal(reduceIndicatorState("attention", { type: "session.status", status: "busy" }), "busy")

const runtimeDir = await mkdtemp(join(tmpdir(), "opencode-session-hook-"))
process.env.XDG_RUNTIME_DIR = runtimeDir
const session = {
  id: "ses_test",
  directory: "/tmp/project",
  title: "Test session",
  time: { updated: 1 },
  location: { directory: "/tmp/project" },
}
let listener
let route = { type: "home" }
let status = "idle"
const context = {
  location: { directory: session.directory },
  data: {
    location: { default: () => ({ directory: session.directory }) },
    listen: (callback) => {
      listener = callback
      return () => { listener = undefined }
    },
    session: {
      get: (id) => id === session.id ? session : undefined,
      status: () => status,
    },
  },
  ui: {
    router: { current: () => route },
    tabs: { enabled: () => false, list: () => [] },
  },
}
const cleanup = await setupSessionStatus(context)
const statePath = join(runtimeDir, "omarchy-opencode-sessions", `${process.pid}.json`)
let persisted = JSON.parse(await readFile(statePath, "utf8"))
assert.equal(persisted.state, "idle")
assert.equal(persisted.title, "")
assert.equal(persisted.version, 1)

route = { type: "session", sessionID: session.id }
status = "running"
listener({ details: { type: "session.execution.started", data: { sessionID: session.id } } })
await new Promise((resolve) => setTimeout(resolve, 20))
persisted = JSON.parse(await readFile(statePath, "utf8"))
assert.equal(persisted.title, session.title)
assert.equal(persisted.state, "busy")

status = "idle"
listener({ details: { type: "session.execution.succeeded", data: { sessionID: session.id } } })
await new Promise((resolve) => setTimeout(resolve, 20))
persisted = JSON.parse(await readFile(statePath, "utf8"))
assert.equal(persisted.state, "idle")

await cleanup()
await assert.rejects(stat(statePath), { code: "ENOENT" })

console.log("state-hook tests passed")
