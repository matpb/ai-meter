package org.mat.pocketmeter

import android.content.SharedPreferences
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.mat.pocketmeter.core.Bar
import org.mat.pocketmeter.core.Payload
import org.mat.pocketmeter.core.RefreshStatus
import org.mat.pocketmeter.core.barValueLabel
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

private val timestampFormat = DateTimeFormatter.ofPattern("MMM d, HH:mm")

// Snapshot of the Prefs state the Activity renders; rebuilt whenever the listener fires.
data class PrefsSnapshot(
    val subStatus: String?,
    val subAt: Long?,
    val payloadJson: String?,
    val payloadReceivedAt: Long?,
    val refreshRequestedAt: Long?,
    val refreshError: String?,
)

class MainActivity : ComponentActivity() {
    private var prefsListener: SharedPreferences.OnSharedPreferenceChangeListener? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme {
                Surface {
                    PocketMeterScreen(activity = this, onRetry = ::retrySubscribe)
                }
            }
        }
    }

    fun readSnapshot(): PrefsSnapshot = PrefsSnapshot(
        subStatus = Prefs.getSubStatus(this),
        subAt = Prefs.getSubAt(this),
        payloadJson = Prefs.getPayloadJson(this),
        payloadReceivedAt = Prefs.getPayloadReceivedAt(this),
        refreshRequestedAt = Prefs.getRefreshRequestedAt(this),
        refreshError = Prefs.getRefreshError(this),
    )

    // Prefs are written from PocketMeterMessagingService, a different component, so the
    // Activity must observe SharedPreferences rather than only read it once at onCreate.
    fun observePrefs(onChange: () -> Unit): SharedPreferences.OnSharedPreferenceChangeListener {
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, _ -> onChange() }
        Prefs.sharedPreferences(this).registerOnSharedPreferenceChangeListener(listener)
        prefsListener = listener
        return listener
    }

    fun stopObservingPrefs() {
        prefsListener?.let { Prefs.sharedPreferences(this).unregisterOnSharedPreferenceChangeListener(it) }
        prefsListener = null
    }

    private fun retrySubscribe() {
        subscribeToTopic(this)
    }
}

@Composable
private fun PocketMeterScreen(activity: MainActivity, onRetry: () -> Unit) {
    var snapshot by remember { mutableStateOf(activity.readSnapshot()) }

    DisposableEffect(Unit) {
        activity.observePrefs { snapshot = activity.readSnapshot() }
        onDispose { activity.stopObservingPrefs() }
    }

    val subscribed = snapshot.subStatus == Prefs.SUB_STATUS_OK
    val subLine = when {
        snapshot.subStatus == null -> "Subscribing to topic \"${BuildConfig.FCM_TOPIC}\"…"
        subscribed -> "Subscribed to topic \"${BuildConfig.FCM_TOPIC}\""
        else -> "Subscribe failed: ${snapshot.subStatus}"
    }

    val payload = remember(snapshot.payloadJson) {
        snapshot.payloadJson?.let { runCatching { parsePayload(it) }.getOrNull() }
    }
    val lastReceivedText = snapshot.payloadReceivedAt?.let {
        ZonedDateTime.ofInstant(Instant.ofEpochSecond(it), ZoneId.systemDefault()).format(timestampFormat)
    } ?: "never"

    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var sending by remember { mutableStateOf(false) }

    // Recomposition otherwise only happens on prefs writes, so a request that never gets
    // answered would stay "Pending" forever; wake up once at the 60s mark to flip to NoReply.
    var now by remember { mutableStateOf(System.currentTimeMillis()) }
    LaunchedEffect(snapshot.refreshRequestedAt) {
        if (snapshot.refreshRequestedAt != null) {
            delay(61_000)
            now = System.currentTimeMillis()
        }
    }
    val refreshStatus = computeRefreshStatus(snapshot.refreshRequestedAt, payload?.ts, now)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .safeDrawingPadding()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("AI Meter", style = MaterialTheme.typography.headlineSmall)
        Text(
            "A desktop collector pushes usage to this device over FCM; nothing here polls or connects out.",
            style = MaterialTheme.typography.bodySmall,
        )

        Text(subLine, style = MaterialTheme.typography.bodyMedium)
        if (!subscribed) {
            Button(onClick = onRetry) { Text("Retry") }
        }

        Text("Last payload received: $lastReceivedText", style = MaterialTheme.typography.bodySmall)

        if (RefreshConfig.enabled) {
            Button(
                enabled = !sending,
                onClick = {
                    scope.launch {
                        sending = true
                        try {
                            requestRefresh(context)
                        } finally {
                            sending = false
                        }
                    }
                },
            ) { Text("Refresh now") }
            when {
                sending -> Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(modifier = Modifier.height(16.dp).width(16.dp))
                    Text("Sending…", style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(start = 8.dp))
                }
                refreshStatus == RefreshStatus.Pending -> Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(modifier = Modifier.height(16.dp).width(16.dp))
                    Text("Asking the desktop…", style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(start = 8.dp))
                }
                refreshStatus == RefreshStatus.NoReply -> Text("Desktop didn't answer. Is it on?", style = MaterialTheme.typography.bodySmall)
            }
            snapshot.refreshError?.let { Text("Error: $it", style = MaterialTheme.typography.bodySmall) }
        }

        Text("Meters", style = MaterialTheme.typography.titleMedium)
        if (payload == null) {
            Text("No payload yet", style = MaterialTheme.typography.bodySmall)
        } else {
            MetersList(payload)
        }
    }
}

@Composable
private fun MetersList(payload: Payload) {
    val now = System.currentTimeMillis() / 1000
    val payloadStale = isPayloadStale(payload.ts, now)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (payloadStale) {
            Text("payload stale", style = MaterialTheme.typography.bodySmall)
        }
        payload.meters.forEach { meter ->
            val meterStale = isMeterStale(meter.age)
            Text("${meter.label}${meter.sub?.let { " · $it" } ?: ""}", style = MaterialTheme.typography.bodyMedium)
            if (!meter.ok) {
                Text("  ${meter.reason ?: "unavailable"}", style = MaterialTheme.typography.bodySmall)
            } else if (meterStale) {
                Text("  stale · ${meter.reason ?: formatAgeShort(meter.age ?: 0L)}", style = MaterialTheme.typography.bodySmall)
            }
            meter.bars.forEach { bar ->
                val noResetInfo = hasNoResetInfo(bar.resetAt, payload.ts)
                val resetLabel = if (noResetInfo) "—" else formatResetLabel(bar.resetAt, now, ZoneId.systemDefault())
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("  ${bar.displayLabel}", style = MaterialTheme.typography.bodySmall, modifier = Modifier.width(56.dp))
                    PaceBar(bar = bar, now = now, noResetInfo = noResetInfo, modifier = Modifier.weight(1f).height(14.dp))
                    Text(
                        "  ${barValueLabel(bar)} reset $resetLabel",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        }
    }
}

@Composable
private fun PaceBar(bar: Bar, now: Long, noResetInfo: Boolean = false, modifier: Modifier = Modifier) {
    val timePct = if (noResetInfo) null else timePctOf(bar.resetAt - now, bar.win)
    Canvas(modifier = modifier.fillMaxWidth()) {
        drawPaceBar(
            canvas = drawContext.canvas.nativeCanvas,
            widthPx = size.width,
            heightPx = size.height,
            pct = bar.pct,
            timePct = timePct,
            fresh = bar.fresh,
            tickWidthPx = 2.dp.toPx(),
        )
    }
}
