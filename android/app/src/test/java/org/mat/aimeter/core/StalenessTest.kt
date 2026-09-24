package org.mat.aimeter.core

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StalenessTest {

    @Test
    fun `payload under the 1800s threshold is not stale`() {
        assertFalse(isPayloadStale(ts = 1000L, now = 1000L + 1800L))
    }

    @Test
    fun `payload over the 1800s threshold is stale`() {
        assertTrue(isPayloadStale(ts = 1000L, now = 1000L + 1801L))
    }

    @Test
    fun `meter age under the 3600s threshold is not stale`() {
        assertFalse(isMeterStale(3600L))
    }

    @Test
    fun `meter age over the 3600s threshold is stale`() {
        assertTrue(isMeterStale(3601L))
    }

    @Test
    fun `null meter age is not stale`() {
        assertFalse(isMeterStale(null))
    }
}
