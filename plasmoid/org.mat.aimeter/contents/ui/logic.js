.pragma library

// Shared by main.qml and the config pages; tests/plasmoid-logic.test.mjs imports a
// copy of this file with a CommonJS export appended.

var BAR_KEYS = {
    claude: [
        { k: "5h", label: "5h" },
        { k: "7d", label: "7d" },
        { k: "model", label: "Per-model weekly (Fable)" }
    ],
    codex: [
        { k: "5h", label: "5h" },
        { k: "7d", label: "7d" }
    ],
    grok: [
        { k: "cli", label: "CLI" },
        { k: "7d", label: "7d" }
    ],
    cursor: [
        { k: "models", label: "Models" },
        { k: "other", label: "Other" },
        { k: "grok", label: "Grok" }
    ]
}

var TYPE_LABELS = { claude: "Claude", codex: "Codex", grok: "Grok", cursor: "Cursor" }

function barKeysFor(type) { return BAR_KEYS[type] || [] }
function typeLabel(type) { return TYPE_LABELS[type] || type }

// ---- duration / age formatting ----

function fmtDur(s) {
    if (s === null || s === undefined) return "—"
    if (s <= 0) return "now"
    var d = Math.floor(s / 86400); s -= d * 86400
    var h = Math.floor(s / 3600); s -= h * 3600
    var m = Math.floor(s / 60)
    if (d > 0) return d + "d " + h + "h"
    if (h > 0) return h + "h " + m + "m"
    return m + "m"
}

function resetText(resetAt, now) {
    if (resetAt === null || resetAt === undefined) return "reset unknown"
    var inSec = resetAt - now
    if (inSec <= 0) return "resets now"
    return "resets in " + fmtDur(inSec)
}

function relTime(ageSec) {
    if (ageSec === null || ageSec === undefined) return "—"
    if (ageSec < 5) return "just now"
    if (ageSec < 60) return Math.floor(ageSec) + "s ago"
    if (ageSec < 3600) return Math.floor(ageSec / 60) + " min ago"
    if (ageSec < 86400) return Math.floor(ageSec / 3600) + "h ago"
    return Math.floor(ageSec / 86400) + "d ago"
}

// ---- pace ----

function timePctOf(resetAt, now, winSec) {
    if (resetAt === null || resetAt === undefined || !winSec) return null
    var resetIn = resetAt - now
    if (resetIn <= 0) return 100
    var e = (winSec - Math.min(resetIn, winSec)) / winSec * 100.0
    return Math.max(0, Math.min(100, e))
}

function barColor(v) {
    var t = Math.max(0, Math.min(100, v)) / 100.0
    var hue = (1.0 - t) * 140.0 / 360.0
    var sat = 0.66 + t * 0.16
    return Qt.hsla(hue, sat, 0.55, 1.0)
}

function paceColor(pct, timePct) {
    if (timePct === null || timePct === undefined) return barColor(pct)
    var m = pct - timePct
    var hue
    if (m <= -8) hue = 140
    else if (m < 0) hue = 55 + (-m / 8) * 85
    else if (m < 8) hue = 55 * (1 - m / 8)
    else hue = 0
    return Qt.hsla(hue / 360.0, 0.72, 0.55, 1.0)
}

// Qt-free pace bucket for Node tests and worst-of selection: "green" | "yellow" | "red".
function paceBucket(pct, timePct) {
    if (timePct === null || timePct === undefined) return "green"
    var m = pct - timePct
    if (m <= -8) return "green"
    if (m < 8) return "yellow"
    return "red"
}

var BUCKET_RANK = { green: 0, yellow: 1, red: 2 }

function worstBucket(meters, now) {
    var worst = "green"
    for (var i = 0; i < (meters || []).length; i++) {
        var m = meters[i]
        if (!m || m.ok === false) continue
        var bars = m.bars || []
        for (var j = 0; j < bars.length; j++) {
            var b = bars[j]
            if (b.pct === null || b.pct === undefined) continue
            var tp = timePctOf(b.reset_at, now, b.win)
            var bucket = paceBucket(b.pct, tp)
            if (BUCKET_RANK[bucket] > BUCKET_RANK[worst]) worst = bucket
        }
    }
    return worst
}

// ---- meter list editing (config page) ----

function genId(type, existingIds) {
    var n = 1
    while (existingIds.indexOf(type + "-" + n) !== -1) n++
    return type + "-" + n
}

function defaultHide(type) {
    return type === "claude" ? ["model"] : []
}

function newMeter(type, existingIds) {
    return {
        id: genId(type, existingIds),
        type: type,
        label: typeLabel(type),
        sub: "",
        panel: false,
        phone: false,
        hide: defaultHide(type),
        icon: "",
        opts: {}
    }
}

function addMeter(meters, type) {
    var ids = meters.map(function (m) { return m.id })
    return meters.concat([newMeter(type, ids)])
}

function removeMeter(meters, id) {
    return meters.filter(function (m) { return m.id !== id })
}

function moveMeter(meters, id, dir) {
    var idx = -1
    for (var i = 0; i < meters.length; i++) if (meters[i].id === id) { idx = i; break }
    if (idx === -1) return meters
    var swapWith = dir === "up" ? idx - 1 : idx + 1
    if (swapWith < 0 || swapWith >= meters.length) return meters
    var out = meters.slice()
    var tmp = out[idx]
    out[idx] = out[swapWith]
    out[swapWith] = tmp
    return out
}

// ---- UTF-8 safe base64, no Buffer / Qt.btoa dependency ----

var B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function toByteString(str) { return unescape(encodeURIComponent(str)) }
function fromByteString(str) { return decodeURIComponent(escape(str)) }

function b64encode(byteStr) {
    var out = "", bits = 0, value = 0
    for (var i = 0; i < byteStr.length; i++) {
        value = (value << 8) | byteStr.charCodeAt(i)
        bits += 8
        while (bits >= 6) {
            bits -= 6
            out += B64_CHARS.charAt((value >> bits) & 0x3F)
        }
    }
    if (bits > 0) out += B64_CHARS.charAt((value << (6 - bits)) & 0x3F)
    while (out.length % 4) out += "="
    return out
}

function b64decode(b64) {
    b64 = b64.replace(/[^A-Za-z0-9+/]/g, "")
    var out = "", bits = 0, value = 0
    for (var i = 0; i < b64.length; i++) {
        value = (value << 6) | B64_CHARS.indexOf(b64.charAt(i))
        bits += 6
        if (bits >= 8) {
            bits -= 8
            out += String.fromCharCode((value >> bits) & 0xFF)
        }
    }
    return out
}

function utf8ToBase64(str) { return b64encode(toByteString(str)) }
function base64ToUtf8(b64) { return fromByteString(b64decode(b64)) }

// ---- misc snapshot helpers ----

function statusWarn(meter) { return meter.ok === false || (meter.reason !== null && meter.reason !== undefined) }

function statusText(meter) {
    if (meter.ok === false) return meter.reason || "error"
    if (meter.reason) return meter.reason
    if (!meter.age || meter.age < 5) return "live"
    return "cached " + relTime(meter.age)
}

function updatedText(ts, now) {
    if (ts === null || ts === undefined) return "Updated —"
    return "Updated " + relTime(Math.max(0, now - ts))
}
