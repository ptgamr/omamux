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

assert.equal(model.suggestSessionName([]), "main")
assert.equal(model.suggestSessionName([{ name: "main" }, { name: "main-2" }]), "main-3")
assert.equal(model.formatAge(100, 100 * 1000 + 30 * 1000), "<1m old")
assert.equal(model.formatAge(100, 100 * 1000 + 3 * 3600 * 1000), "3h old")
assert.equal(model.clientLabel(0), "available")
assert.equal(model.clientLabel(2), "2 clients")
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

assert.equal(
  JSON.stringify(model.favoriteOrder([
    { name: "one", favorite: true },
    { name: "two", favorite: true },
    { name: "three", favorite: false },
  ])),
  JSON.stringify(["one", "two"]),
)

console.log("PASS: omamux model")
