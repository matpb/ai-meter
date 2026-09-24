package org.mat.aimeter.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BarWidthTest {

    // Production fixed columns: label 44 + spacer 4 + value 44 + reset 64 = 156, padding 16.
    private val fixedColumnsDp = 156f
    private val outerPaddingDp = 16f

    @Test
    fun `wide widget leaves plenty of room for the bar`() {
        val barWidthDp = computeBarWidthDp(320f, fixedColumnsDp, outerPaddingDp)
        assertTrue(barWidthDp >= 120f)
    }

    @Test
    fun `tiny widget floors at 40dp instead of collapsing`() {
        val barWidthDp = computeBarWidthDp(50f, fixedColumnsDp, outerPaddingDp)
        assertEquals(40f, barWidthDp, 0.001f)
    }
}
