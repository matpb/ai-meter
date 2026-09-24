// Loads contents/ui/logic.js as CommonJS by stripping the QML `.pragma library`
// line and appending an export block, so the exact shipped file is under test.
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import vm from "node:vm"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const src = fs.readFileSync(
    path.join(__dirname, "..", "plasmoid", "org.mat.aimeter", "contents", "ui", "logic.js"),
    "utf8"
).replace(/^\.pragma library\s*/, "")

const exportNames = [
    "barKeysFor", "typeLabel", "fmtDur", "resetText", "relTime", "timePctOf",
    "paceBucket", "worstBucket", "genId", "defaultHide", "newMeter", "addMeter",
    "removeMeter", "moveMeter", "utf8ToBase64", "base64ToUtf8", "statusWarn",
    "statusText", "updatedText"
]

const sandbox = { Qt: { hsla: () => "" }, unescape, escape, encodeURIComponent, decodeURIComponent }
vm.createContext(sandbox)
vm.runInContext(src + "\nthis.__exports = { " + exportNames.join(", ") + " };", sandbox)
const L = sandbox.__exports

let passed = 0
function test(name, fn) {
    fn()
    passed++
    console.log("ok - " + name)
}

test("fmtDur formats days/hours/minutes", () => {
    assert.equal(L.fmtDur(0), "now")
    assert.equal(L.fmtDur(90), "1m")
    assert.equal(L.fmtDur(3700), "1h 1m")
    assert.equal(L.fmtDur(90000), "1d 1h")
    assert.equal(L.fmtDur(null), "—")
})

test("relTime buckets by magnitude", () => {
    assert.equal(L.relTime(2), "just now")
    assert.equal(L.relTime(360), "6 min ago")
    assert.equal(L.relTime(7200), "2h ago")
    assert.equal(L.relTime(172800), "2d ago")
})

test("timePctOf tracks elapsed fraction of the window", () => {
    const now = 1000
    assert.equal(L.timePctOf(now + 18000, now, 18000), 0)
    assert.equal(L.timePctOf(now + 9000, now, 18000), 50)
    assert.equal(L.timePctOf(now - 5, now, 18000), 100)
    assert.equal(L.timePctOf(null, now, 18000), null)
})

test("paceBucket flags ahead-of-clock usage as red, comfortable as green", () => {
    assert.equal(L.paceBucket(90, 20), "red")
    assert.equal(L.paceBucket(10, 50), "green")
    assert.equal(L.paceBucket(50, 50), "yellow")
    assert.equal(L.paceBucket(50, null), "green")
})

test("worstBucket picks the worst bar across all ok meters", () => {
    const now = 1000
    const meters = [
        { ok: true, bars: [{ pct: 5, reset_at: now + 17000, win: 18000 }] },
        { ok: true, bars: [{ pct: 95, reset_at: now + 17900, win: 18000 }] },
        { ok: false, bars: [{ pct: 100, reset_at: now, win: 18000 }] }
    ]
    assert.equal(L.worstBucket(meters, now), "red")
})

test("genId picks the lowest free suffix for the type", () => {
    assert.equal(L.genId("claude", []), "claude-1")
    assert.equal(L.genId("claude", ["claude-1", "claude-2"]), "claude-3")
    assert.equal(L.genId("claude", ["claude-1", "claude-3"]), "claude-2")
})

test("addMeter/removeMeter/moveMeter round-trip a meter list", () => {
    let meters = []
    meters = L.addMeter(meters, "claude")
    meters = L.addMeter(meters, "codex")
    assert.equal(meters.length, 2)
    assert.equal(meters[0].id, "claude-1")
    assert.equal(JSON.stringify(meters[0].hide), JSON.stringify(["model"]))
    assert.equal(JSON.stringify(meters[1].hide), JSON.stringify([]))

    meters = L.moveMeter(meters, "codex-1", "up")
    assert.equal(meters[0].id, "codex-1")
    meters = L.moveMeter(meters, "codex-1", "up")
    assert.equal(meters[0].id, "codex-1", "moving the first item up is a no-op")

    meters = L.removeMeter(meters, "claude-1")
    assert.equal(meters.length, 1)
    assert.equal(meters[0].id, "codex-1")
})

test("utf8ToBase64/base64ToUtf8 round-trips non-ASCII text", () => {
    const s = "Compte perso — é à ç 中文"
    const b64 = L.utf8ToBase64(s)
    assert.equal(L.base64ToUtf8(b64), s)
    assert.equal(L.utf8ToBase64("a"), "YQ==")
    assert.equal(L.utf8ToBase64(""), "")
})

test("statusText/statusWarn reflect ok/reason/age", () => {
    assert.equal(L.statusText({ ok: true, age: 0 }), "live")
    assert.equal(L.statusText({ ok: true, age: 400 }), "cached 6 min ago")
    assert.equal(L.statusText({ ok: false, reason: "network error" }), "network error")
    assert.equal(L.statusWarn({ ok: true, reason: null }), false)
    assert.equal(L.statusWarn({ ok: true, reason: "using cached data" }), true)
    assert.equal(L.statusWarn({ ok: false }), true)
})

test("barKeysFor returns the contract's bar keys per type", () => {
    assert.equal(JSON.stringify(L.barKeysFor("claude").map(b => b.k)), JSON.stringify(["5h", "7d", "model"]))
    assert.equal(JSON.stringify(L.barKeysFor("cursor").map(b => b.k)), JSON.stringify(["models", "other", "grok"]))
})

console.log(`\n${passed} tests passed`)
