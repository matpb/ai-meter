package org.mat.aimeter.core

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF

const val TRACK_COLOR_ARGB = 0xFF3A3A3A.toInt()
const val TICK_COLOR_ARGB = 0xFFEDEDED.toInt()

// Bar width available after fixed columns/padding, floored so it never collapses to near-zero.
fun computeBarWidthDp(widgetWidthDp: Float, fixedColumnsDp: Float, outerPaddingDp: Float, floorDp: Float = 40f): Float =
    (widgetWidthDp - fixedColumnsDp - outerPaddingDp).coerceAtLeast(floorDp)

private fun scaleAlpha(argb: Int, alphaScale: Float): Int {
    val a = ((argb ushr 24) and 0xFF)
    val scaled = (a * alphaScale).toInt().coerceIn(0, 255)
    return (scaled shl 24) or (argb and 0x00FFFFFF)
}

// Draws track + pace-colored fill + time-pace tick onto an existing canvas. Shared by the Glance
// widget (via a Bitmap) and the plain Compose activity list (via a Compose Canvas' nativeCanvas).
fun drawPaceBar(
    canvas: Canvas,
    widthPx: Float,
    heightPx: Float,
    pct: Int,
    timePct: Double?,
    fresh: Boolean,
    tickWidthPx: Float,
    alphaScale: Float = 1f,
) {
    val cornerRadius = heightPx / 2f
    val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = scaleAlpha(TRACK_COLOR_ARGB, alphaScale) }
    canvas.drawRoundRect(RectF(0f, 0f, widthPx, heightPx), cornerRadius, cornerRadius, trackPaint)

    if (!fresh) {
        val fillWidth = (pct.coerceIn(0, 100) / 100f) * widthPx
        if (fillWidth > 0f) {
            val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = scaleAlpha(paceColorArgb(pct, timePct), alphaScale)
            }
            canvas.drawRoundRect(RectF(0f, 0f, fillWidth, heightPx), cornerRadius, cornerRadius, fillPaint)
        }
    }

    if (timePct != null) {
        val tickX = (timePct.toFloat() / 100f) * widthPx
        val tickPaint = Paint().apply { color = scaleAlpha(TICK_COLOR_ARGB, alphaScale) }
        val half = tickWidthPx / 2f
        canvas.drawRect(
            RectF(
                (tickX - half).coerceIn(0f, widthPx - tickWidthPx),
                0f,
                (tickX - half).coerceIn(0f, widthPx - tickWidthPx) + tickWidthPx,
                heightPx,
            ),
            tickPaint,
        )
    }
}
