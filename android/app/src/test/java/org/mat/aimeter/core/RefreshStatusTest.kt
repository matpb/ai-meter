package org.mat.aimeter.core

import org.junit.Assert.assertEquals
import org.junit.Test

class RefreshStatusTest {

    @Test
    fun `no request is idle`() {
        assertEquals(RefreshStatus.Idle, computeRefreshStatus(null, null, 10_000L))
    }

    @Test
    fun `unanswered request under 60s is pending`() {
        assertEquals(RefreshStatus.Pending, computeRefreshStatus(1_000L, null, 1_000L + 59_000L))
    }

    @Test
    fun `unanswered request at 60s or older is no reply`() {
        assertEquals(RefreshStatus.NoReply, computeRefreshStatus(1_000L, null, 1_000L + 60_000L))
    }

    @Test
    fun `payload at or after requestedAt minus 5s clears to idle`() {
        // payloadTs in seconds; requestedAt in ms. payloadMs = 10_000, requestedAt - 5000 = 10_000.
        assertEquals(RefreshStatus.Idle, computeRefreshStatus(15_000L, 10L, 15_100L))
    }

    @Test
    fun `payload exactly at the 5s skew boundary clears to idle`() {
        // payloadMs = 15_000, requestedAt - 5000 = 15_000.
        assertEquals(RefreshStatus.Idle, computeRefreshStatus(20_000L, 15L, 20_100L))
    }

    @Test
    fun `payload older than the skew window leaves request pending`() {
        // payloadMs = 9_000, requestedAt - 5000 = 10_000: payload too old to satisfy the request.
        assertEquals(RefreshStatus.Pending, computeRefreshStatus(15_000L, 9L, 15_100L))
    }

    @Test
    fun `stale payload with request past 60s is no reply`() {
        // payloadMs = 50_000, requestedAt - 5000 = 95_000: payload too old to satisfy the request.
        assertEquals(RefreshStatus.NoReply, computeRefreshStatus(100_000L, 50L, 100_000L + 61_000L))
    }
}
