package org.mat.pocketmeter.core

import kotlin.math.roundToInt

// How far through the reset window we are, by elapsed time (0..100), or null with no reference.
fun timePctOf(resetInSeconds: Long, winSeconds: Int?): Double? {
    if (winSeconds == null || resetInSeconds <= 0) return null
    val win = winSeconds.toDouble()
    val e = (win - minOf(resetInSeconds.toDouble(), win)) / win * 100.0
    return e.coerceIn(0.0, 100.0)
}

// True when a bar's reset carries no real info (e.g. a stale fallback reported reset_in: 0).
fun hasNoResetInfo(resetAtEpochSeconds: Long, payloadTsEpochSeconds: Long): Boolean =
    resetAtEpochSeconds <= payloadTsEpochSeconds

// hueDeg in 0..360, sat/light in 0..1. Packs as 0xAARRGGBB, matching android.graphics.Color.argb.
fun hslToArgb(hueDeg: Double, sat: Double, light: Double, alpha: Int = 255): Int {
    val h = (((hueDeg % 360.0) + 360.0) % 360.0) / 360.0
    val r: Double
    val g: Double
    val b: Double
    if (sat == 0.0) {
        r = light; g = light; b = light
    } else {
        val q = if (light < 0.5) light * (1 + sat) else light + sat - light * sat
        val p = 2 * light - q
        r = hueToRgbComponent(p, q, h + 1.0 / 3.0)
        g = hueToRgbComponent(p, q, h)
        b = hueToRgbComponent(p, q, h - 1.0 / 3.0)
    }
    val ri = (r * 255.0).roundToInt().coerceIn(0, 255)
    val gi = (g * 255.0).roundToInt().coerceIn(0, 255)
    val bi = (b * 255.0).roundToInt().coerceIn(0, 255)
    return (alpha shl 24) or (ri shl 16) or (gi shl 8) or bi
}

private fun hueToRgbComponent(p: Double, q: Double, t0: Double): Double {
    var t = t0
    if (t < 0) t += 1.0
    if (t > 1) t -= 1.0
    return when {
        t < 1.0 / 6.0 -> p + (q - p) * 6.0 * t
        t < 1.0 / 2.0 -> q
        t < 2.0 / 3.0 -> p + (q - p) * (2.0 / 3.0 - t) * 6.0
        else -> p
    }
}

// Continuous green -> amber -> red as usage climbs, used when there's no time reference.
private fun barColorArgb(pct: Int): Int {
    val t = pct.coerceIn(0, 100) / 100.0
    val hue = (1.0 - t) * 140.0
    val sat = 0.66 + t * 0.16
    return hslToArgb(hue, sat, 0.55)
}

// Colour by pace: margin = usage% - time%. Under the clock is green, ahead of it is red.
fun paceColorArgb(pct: Int, timePct: Double?): Int {
    if (timePct == null) return barColorArgb(pct)
    val m = pct - timePct
    val hue = when {
        m <= -8.0 -> 140.0
        m < 0.0 -> 55.0 + (-m / 8.0) * 85.0
        m < 8.0 -> 55.0 * (1.0 - m / 8.0)
        else -> 0.0
    }
    return hslToArgb(hue, 0.72, 0.55)
}
