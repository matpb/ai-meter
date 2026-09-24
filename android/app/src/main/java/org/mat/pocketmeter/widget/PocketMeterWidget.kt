package org.mat.pocketmeter.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import org.mat.pocketmeter.MainActivity
import org.mat.pocketmeter.Prefs
import org.mat.pocketmeter.RefreshConfig
import org.mat.pocketmeter.core.Bar
import org.mat.pocketmeter.core.Meter
import org.mat.pocketmeter.core.Payload
import org.mat.pocketmeter.core.RefreshStatus
import org.mat.pocketmeter.core.barValueLabel
import org.mat.pocketmeter.core.computeBarWidthDp
import org.mat.pocketmeter.core.computeRefreshStatus
import org.mat.pocketmeter.core.displayLabel
import org.mat.pocketmeter.core.drawPaceBar
import org.mat.pocketmeter.core.formatAgeShort
import org.mat.pocketmeter.core.formatResetLabel
import org.mat.pocketmeter.core.hasNoResetInfo
import org.mat.pocketmeter.core.isMeterStale
import org.mat.pocketmeter.core.isPayloadStale
import org.mat.pocketmeter.core.parsePayload
import org.mat.pocketmeter.core.timePctOf

private val hhmm = DateTimeFormatter.ofPattern("HH:mm")

private val bgDark = ColorProvider(Color(0xFF121212))
private val fgLight = ColorProvider(Color(0xFFEDEDED))
private val fgMuted = ColorProvider(Color(0xFF9A9A9A))

// Fixed columns in BarRow besides the bar itself: k label, spacer, value, reset label.
private val BAR_LABEL_DP = 44
private val BAR_SPACER_DP = 4
private val BAR_VALUE_DP = 44
private val BAR_RESET_DP = 64
private val BAR_HEIGHT_DP = 14
private val BAR_TICK_DP = 2

class PocketMeterWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val rawJson = Prefs.getPayloadJson(context)
        val payload = rawJson?.let { runCatching { parsePayload(it) }.getOrNull() }
        provideContent {
            GlanceTheme {
                WidgetContent(payload)
            }
        }
    }
}

@Composable
private fun WidgetContent(payload: Payload?) {
    val context = LocalContext.current
    val refreshStatus = if (RefreshConfig.enabled) {
        computeRefreshStatus(
            Prefs.getRefreshRequestedAt(context),
            payload?.ts,
            System.currentTimeMillis(),
        )
    } else {
        RefreshStatus.Idle
    }

    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(bgDark)
            .padding(8.dp)
            .clickable(actionStartActivity(MainActivity::class.java))
    ) {
        val now = System.currentTimeMillis() / 1000
        val stale = payload?.let { isPayloadStale(it.ts, now) } ?: false
        val baseHeaderText = if (payload == null) {
            "Waiting for hub…"
        } else {
            val updated = ZonedDateTime.ofInstant(Instant.ofEpochSecond(payload.ts), ZoneId.systemDefault())
            if (stale) "stale · ${updated.format(hhmm)}" else "updated ${updated.format(hhmm)}"
        }
        val statusSuffix = when (refreshStatus) {
            RefreshStatus.Pending -> " · refreshing…"
            RefreshStatus.NoReply -> " · no reply"
            RefreshStatus.Idle -> ""
        }
        val headerColor = if (stale || payload == null) fgMuted else fgLight

        Row(verticalAlignment = Alignment.CenterVertically, modifier = GlanceModifier.fillMaxWidth()) {
            Text(
                "$baseHeaderText$statusSuffix",
                style = TextStyle(color = headerColor, fontWeight = FontWeight.Bold),
                modifier = GlanceModifier.defaultWeight(),
            )
            if (RefreshConfig.enabled) {
                Text(
                    "⟳",
                    style = TextStyle(color = fgLight, fontWeight = FontWeight.Bold),
                    modifier = GlanceModifier.clickable(actionRunCallback<RefreshAction>()),
                )
            }
        }

        if (payload == null) return@Column
        Spacer(modifier = GlanceModifier.size(4.dp))

        LazyColumn(modifier = GlanceModifier.fillMaxSize()) {
            items(payload.meters) { meter -> MeterRow(meter, stale, payload.ts) }
        }
    }
}

@Composable
private fun MeterRow(meter: Meter, payloadStale: Boolean, payloadTs: Long) {
    val meterStale = isMeterStale(meter.age)
    val dim = payloadStale || meterStale || !meter.ok
    val labelColor = if (dim) fgMuted else fgLight
    Column(modifier = GlanceModifier.fillMaxWidth().padding(vertical = 2.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                meter.label,
                style = TextStyle(color = labelColor, fontWeight = FontWeight.Bold, fontSize = 12.sp),
            )
            if (meter.sub != null) {
                Spacer(modifier = GlanceModifier.width(4.dp))
                Text("· ${meter.sub}", style = TextStyle(color = fgMuted, fontSize = 12.sp))
            }
        }
        // ok:false wins the message slot; a stale-but-ok reading gets its own line below.
        if (!meter.ok) {
            Text(meter.reason ?: "unavailable", style = TextStyle(color = fgMuted, fontSize = 12.sp))
            return@Column
        }
        if (meterStale) {
            val staleText = meter.reason ?: formatAgeShort(meter.age ?: 0L)
            Text("stale · $staleText", style = TextStyle(color = fgMuted, fontSize = 12.sp))
        }
        meter.bars.forEach { bar -> BarRow(bar, payloadStale || meterStale, payloadTs) }
    }
}

@Composable
private fun BarRow(bar: Bar, dimmed: Boolean, payloadTs: Long) {
    val context = LocalContext.current
    val now = System.currentTimeMillis() / 1000
    val noResetInfo = hasNoResetInfo(bar.resetAt, payloadTs)
    val resetLabel = if (noResetInfo) "—" else formatResetLabel(bar.resetAt, now, ZoneId.systemDefault())
    val timePct = if (noResetInfo) null else timePctOf(bar.resetAt - now, bar.win)

    val density = context.resources.displayMetrics.density
    val widgetWidthDp = LocalSize.current.width.value
    val fixedColumnsDp = BAR_LABEL_DP + BAR_SPACER_DP + BAR_VALUE_DP + BAR_RESET_DP
    val outerPaddingDp = 16 // WidgetContent's 8dp horizontal padding, both sides
    val barWidthDp = computeBarWidthDp(widgetWidthDp, fixedColumnsDp.toFloat(), outerPaddingDp.toFloat())
    val barWidthPx = barWidthDp * density
    val barHeightPx = BAR_HEIGHT_DP * density
    val tickWidthPx = BAR_TICK_DP * density
    val alphaScale = if (dimmed) 0.4f else 1f

    val bitmap = Bitmap.createBitmap(barWidthPx.toInt(), barHeightPx.toInt(), Bitmap.Config.ARGB_8888)
    drawPaceBar(
        canvas = Canvas(bitmap),
        widthPx = barWidthPx,
        heightPx = barHeightPx,
        pct = bar.pct,
        timePct = timePct,
        fresh = bar.fresh,
        tickWidthPx = tickWidthPx,
        alphaScale = alphaScale,
    )

    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(
            bar.displayLabel,
            style = TextStyle(color = fgMuted, fontSize = 12.sp),
            modifier = GlanceModifier.width(BAR_LABEL_DP.dp),
        )
        Image(
            provider = ImageProvider(bitmap),
            contentDescription = "${bar.displayLabel} usage ${bar.pct}%",
            contentScale = ContentScale.FillBounds,
            modifier = GlanceModifier.defaultWeight().height(BAR_HEIGHT_DP.dp),
        )
        Spacer(modifier = GlanceModifier.width(BAR_SPACER_DP.dp))
        Text(
            barValueLabel(bar),
            style = TextStyle(color = fgLight, fontSize = 12.sp),
            modifier = GlanceModifier.width(BAR_VALUE_DP.dp),
        )
        Text(
            resetLabel,
            style = TextStyle(color = fgMuted, fontSize = 12.sp),
            modifier = GlanceModifier.width(BAR_RESET_DP.dp),
        )
    }
}
