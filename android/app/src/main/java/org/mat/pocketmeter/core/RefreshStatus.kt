package org.mat.pocketmeter.core

private const val PENDING_TIMEOUT_MS = 60_000L
private const val CLOCK_SKEW_MS = 5_000L

sealed class RefreshStatus {
    object Idle : RefreshStatus()
    object Pending : RefreshStatus()
    object NoReply : RefreshStatus()
}

// requestedAtMs: when the refresh was requested, or null if never requested.
// payloadTsSeconds: the ts of the most recently received payload, or null if none yet.
fun computeRefreshStatus(requestedAtMs: Long?, payloadTsSeconds: Long?, nowMs: Long): RefreshStatus {
    if (requestedAtMs == null) return RefreshStatus.Idle
    val payloadMs = payloadTsSeconds?.let { it * 1000 }
    if (payloadMs != null && payloadMs >= requestedAtMs - CLOCK_SKEW_MS) return RefreshStatus.Idle
    return if (nowMs - requestedAtMs < PENDING_TIMEOUT_MS) RefreshStatus.Pending else RefreshStatus.NoReply
}
