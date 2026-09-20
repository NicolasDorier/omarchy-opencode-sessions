import assert from "node:assert/strict"
import { mkdtemp, readFile, stat } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import OpenCodeSessionStatus, { isInteractiveTui, reduceIndicatorState } from "../opencode/omarchy-session-status.ts"

assert.equal(reduceIndicatorState("idle", { type: "session.status", status: "busy" }), "busy")
assert.equal(reduceIndicatorState("idle", { type: "session.status", status: "retry" }), "busy")
assert.equal(reduceIndicatorState("busy", { type: "session.idle" }), "idle")
assert.equal(reduceIndicatorState("busy", { type: "question.asked" }), "attention")
assert.equal(reduceIndicatorState("busy", { type: "permission.asked" }), "attention")
assert.equal(reduceIndicatorState("attention", { type: "session.idle" }), "attention")
assert.equal(reduceIndicatorState("attention", { type: "session.status", status: "idle" }), "attention")
assert.equal(reduceIndicatorState("attention", { type: "question.replied" }), "busy")
assert.equal(reduceIndicatorState("attention", { type: "permission.replied" }), "busy")
assert.equal(reduceIndicatorState("busy", { type: "session.error", errorName: "APIError" }), "attention")
assert.equal(reduceIndicatorState("busy", { type: "session.error", errorName: "MessageAbortedError" }), "idle")
assert.equal(reduceIndicatorState("attention", { type: "session.status", status: "busy" }), "busy")
assert.equal(reduceIndicatorState("busy", {
  type: "message.updated", role: "assistant", finish: "tool-calls", completed: true,
}), "busy")
assert.equal(reduceIndicatorState("busy", {
  type: "message.updated", role: "assistant", finish: "stop", completed: true,
}), "idle")
assert.equal(reduceIndicatorState("busy", {
  type: "message.updated", role: "assistant", finish: "error", completed: true,
}), "busy")
assert.equal(isInteractiveTui(["/usr/bin/opencode", "--auto", "."]), true)
assert.equal(isInteractiveTui(["/usr/bin/opencode", "run", "hello"]), false)
assert.equal(isInteractiveTui(["/usr/bin/opencode", "debug", "wait"]), false)

const runtimeDir = await mkdtemp(join(tmpdir(), "opencode-session-hook-"))
process.env.XDG_RUNTIME_DIR = runtimeDir
const session = {
  id: "ses_test",
  directory: "/tmp/project",
  title: "Test session",
  time: { updated: 1 },
}
const hooks = await OpenCodeSessionStatus({
  directory: session.directory,
})
const statePath = join(runtimeDir, "omarchy-opencode-sessions", `${process.pid}.json`)
let persisted = JSON.parse(await readFile(statePath, "utf8"))
assert.equal(persisted.state, "idle")
assert.equal(persisted.title, "")

await hooks.event({
  event: {
    type: "session.updated",
    properties: { info: session },
  },
})
persisted = JSON.parse(await readFile(statePath, "utf8"))
assert.equal(persisted.title, session.title)

await hooks.event({
  event: {
    type: "session.status",
    properties: { sessionID: session.id, status: { type: "busy" } },
  },
})
persisted = JSON.parse(await readFile(statePath, "utf8"))
assert.equal(persisted.state, "busy")

await hooks.event({
  event: {
    type: "message.updated",
    properties: {
      info: {
        id: "msg_test",
        sessionID: session.id,
        role: "assistant",
        finish: "stop",
        time: { completed: Date.now() },
      },
    },
  },
})
persisted = JSON.parse(await readFile(statePath, "utf8"))
assert.equal(persisted.state, "idle")

await hooks.dispose()
await assert.rejects(stat(statePath), { code: "ENOENT" })

console.log("state-hook tests passed")
