package org.mat.pocketmeter.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PaceColorTest {

    @Test
    fun `timePctOf is null with no window`() {
        assertNull(timePctOf(100, null))
    }

    @Test
    fun `timePctOf is null when resetIn is not positive`() {
        assertNull(timePctOf(0, 3600))
        assertNull(timePctOf(-5, 3600))
    }

    @Test
    fun `timePctOf mid window`() {
        // 1h window, 15min left -> 45min elapsed -> 75%
        assertEquals(75.0, timePctOf(900, 3600)!!, 0.001)
    }

    @Test
    fun `timePctOf clamps to 0 when resetIn exceeds the window`() {
        assertEquals(0.0, timePctOf(7200, 3600)!!, 0.001)
    }

    @Test
    fun `pace branch far under pace is green hue`() {
        assertEquals(hslToArgb(140.0, 0.72, 0.55), paceColorArgb(pct = 10, timePct = 30.0))
    }

    @Test
    fun `pace branch slightly under pace interpolates`() {
        // m = -4 -> hue = 55 + (4/8)*85 = 97.5
        assertEquals(hslToArgb(97.5, 0.72, 0.55), paceColorArgb(pct = 26, timePct = 30.0))
    }

    @Test
    fun `pace branch slightly ahead of pace interpolates`() {
        // m = 4 -> hue = 55 * (1 - 4/8) = 27.5
        assertEquals(hslToArgb(27.5, 0.72, 0.55), paceColorArgb(pct = 34, timePct = 30.0))
    }

    @Test
    fun `pace branch far ahead of pace is red hue`() {
        assertEquals(hslToArgb(0.0, 0.72, 0.55), paceColorArgb(pct = 50, timePct = 30.0))
    }

    @Test
    fun `fallback with no time reference matches the continuous gradient`() {
        assertEquals(hslToArgb(140.0, 0.66, 0.55), paceColorArgb(pct = 0, timePct = null))
        assertEquals(hslToArgb(0.0, 0.82, 0.55), paceColorArgb(pct = 100, timePct = null))
    }
}
