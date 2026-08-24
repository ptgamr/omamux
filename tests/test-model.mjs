import assert from "node:assert/strict"
import fs from "node:fs"
import vm from "node:vm"

const source = fs.readFileSync(new URL("../Model.js", import.meta.url), "utf8")
const model = { Date, JSON, Math, Number, String, Array, isFinite }
vm.createContext(model)
vm.runInContext(source, model, { filename: "Model.js" })

assert.equal(model.validationError(""), "Enter a session name")
assert.equal(model.validationError("bad.name"), "Session names cannot contain . or :")
assert.equal(model.validationError("bad:name"), "Session names cannot contain . or :")
assert.equal(model.validationError("client work; echo safe"), "")
assert.equal(model.normalizedSessionName("  main  "), "main")
assert.equal(
  model.themeColor('blue = "#7daea3"\nyellow = "#d8a657"', "blue", "#000000"),
  "#7daea3",
)
assert.equal(model.themeColor('blue = "#7daea3"', "yellow", "#e0af68"), "#e0af68")

assert.equal(model.suggestSessionName([]), "main")
assert.equal(model.suggestSessionName([{ name: "main" }, { name: "main-2" }]), "main-3")
assert.equal(model.formatAge(100, 100 * 1000 + 30 * 1000), "<1m old")
assert.equal(model.formatAge(100, 100 * 1000 + 3 * 3600 * 1000), "3h old")
assert.equal(model.clientLabel(0), "")
assert.equal(model.clientLabel(2), "2 clients")
assert.equal(model.workspaceLabel({ desktop: { workspace: { id: 8 } } }), "ws 8")
assert.equal(model.workspaceLabel({ desktop: null }), "")
assert.equal(
  model.sessionMeta({ name: "main", favorite: true, running: false }, Date.now()),
  "Not running · favorite saved",
)
assert.equal(
  model.sessionMeta({ windows: 2, createdAt: 100, attachedClients: 0 }, 100 * 1000 + 24 * 3600 * 1000),
  "2 windows · 1d old",
)
assert.equal(
  model.sessionMeta({
    windows: 2,
    createdAt: 100,
    attachedClients: 1,
    desktop: { workspace: { id: 8 } },
  }, 100 * 1000 + 24 * 3600 * 1000),
  "2 windows · 1d old · 1 client · ws 8",
)
assert.equal(model.movedSelection(0, 3, 1, false), 0)
assert.equal(model.movedSelection(0, 3, -1, false), 2)
assert.equal(model.movedSelection(0, 3, 1, true), 1)
assert.equal(model.movedSelection(2, 3, 1, true), 2)
assert.equal(model.pointerMoved(Number.NaN, Number.NaN, 20, 30, 0.5), true)
assert.equal(model.pointerMoved(20, 30, 20, 30, 0.5), false)
assert.equal(model.pointerMoved(20, 30, 20.3, 30.3, 0.5), false)
assert.equal(model.pointerMoved(20, 30, 21, 30, 0.5), true)
assert.equal(
  model.sessionMeta({ windows: 2, createdAt: 100, attachedClients: 1 }, 100 * 1000 + 24 * 3600 * 1000),
  "2 windows · 1d old · 1 client",
)

const parsed = model.parseListPayload(JSON.stringify({
  ok: true,
  host: { id: "local", name: "arch" },
  tmux: { available: true, version: "tmux 3.7c" },
  sessions: [{ name: "main" }],
}))
assert.equal(parsed.ok, true)
assert.equal(parsed.host.name, "arch")
assert.equal(parsed.sessions[0].name, "main")
assert.equal(model.parseListPayload("not json").ok, false)

const detail = model.parseDetailPayload(JSON.stringify({
  ok: true,
  session: "main",
  windows: [{ index: 0, name: "shell", panes: [{ index: 0, command: "zsh" }] }],
}))
assert.equal(detail.ok, true)
assert.equal(detail.session, "main")
assert.equal(detail.windows[0].panes[0].command, "zsh")
assert.equal(model.parseDetailPayload("not json").ok, false)
assert.deepEqual(
  JSON.parse(JSON.stringify(model.detailRows([
    {
      index: 0,
      name: "editor",
      panes: [
        { index: 0, command: "zsh" },
        { index: 1, command: "nvim" },
      ],
    },
    { index: 1, name: "server", panes: [{ index: 0, command: "node" }] },
  ]).map((row) => ({
    kind: row.kind,
    window: row.window.index,
    pane: row.pane ? row.pane.index : null,
    lastPane: row.lastPane === true,
  })))),
  [
    { kind: "window", window: 0, pane: null, lastPane: false },
    { kind: "pane", window: 0, pane: 0, lastPane: false },
    { kind: "pane", window: 0, pane: 1, lastPane: true },
    { kind: "window", window: 1, pane: null, lastPane: false },
    { kind: "pane", window: 1, pane: 0, lastPane: true },
  ],
)

assert.equal(
  JSON.stringify(model.favoriteOrder([
    { name: "one", favorite: true },
    { name: "two", favorite: true },
    { name: "three", favorite: false },
  ])),
  JSON.stringify(["one", "two"]),
)

const starred = model.toggledFavoriteRows([
  { name: "one", favorite: true },
  { name: "two", favorite: false },
  { name: "three", favorite: false },
], 2)
assert.equal(starred.favorite, true)
assert.equal(starred.targetIndex, 0)
assert.equal(
  JSON.stringify(starred.rows.map((row) => [row.name, row.favorite])),
  JSON.stringify([["three", true], ["one", true], ["two", false]]),
)

const unstarred = model.toggledFavoriteRows([
  { name: "one", favorite: true },
  { name: "two", favorite: true },
  { name: "three", favorite: false },
], 0)
assert.equal(unstarred.favorite, false)
assert.equal(unstarred.targetIndex, 1)
assert.equal(
  JSON.stringify(unstarred.rows.map((row) => [row.name, row.favorite])),
  JSON.stringify([["two", true], ["one", false], ["three", false]]),
)

const rankedUnstarred = model.toggledFavoriteRows([
  { name: "two", favorite: true, nativeOrder: 2 },
  { name: "three", favorite: true, nativeOrder: 3 },
  { name: "zero", favorite: false, nativeOrder: 0 },
  { name: "one", favorite: false, nativeOrder: 1 },
  { name: "four", favorite: false, nativeOrder: 4 },
], 0)
assert.equal(rankedUnstarred.targetIndex, 3)
assert.equal(
  JSON.stringify(rankedUnstarred.rows.map((row) => row.name)),
  JSON.stringify(["three", "zero", "one", "two", "four"]),
)

assert.deepEqual(
  [0, 1, 2, 3, 4, 5].map((index) => model.reorderOffset(index, 4, 0, 48)),
  [48, 48, 48, 48, -192, 0],
)
assert.deepEqual(
  [0, 1, 2].map((index) => model.reorderOffset(index, 0, 1, 48)),
  [48, -48, 0],
)

console.log("PASS: omamux model")
