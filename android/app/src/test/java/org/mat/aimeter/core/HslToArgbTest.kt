package org.mat.aimeter.core

import org.junit.Assert.assertEquals
import org.junit.Test

private fun red(argb: Int) = (argb shr 16) and 0xFF
private fun green(argb: Int) = (argb shr 8) and 0xFF
private fun blue(argb: Int) = argb and 0xFF
private fun alpha(argb: Int) = (argb shr 24) and 0xFF

class HslToArgbTest {

    @Test
    fun `pure red at hue 0`() {
        val c = hslToArgb(0.0, 1.0, 0.5)
        assertEquals(255, red(c))
        assertEquals(0, green(c))
        assertEquals(0, blue(c))
        assertEquals(255, alpha(c))
    }

    @Test
    fun `pure green at hue 120`() {
        val c = hslToArgb(120.0, 1.0, 0.5)
        assertEquals(0, red(c))
        assertEquals(255, green(c))
        assertEquals(0, blue(c))
    }

    @Test
    fun `pure blue at hue 240`() {
        val c = hslToArgb(240.0, 1.0, 0.5)
        assertEquals(0, red(c))
        assertEquals(0, green(c))
        assertEquals(255, blue(c))
    }

    @Test
    fun `zero saturation is a gray`() {
        val c = hslToArgb(0.0, 0.0, 0.5)
        assertEquals(red(c), green(c))
        assertEquals(green(c), blue(c))
        assertEquals(128, red(c))
    }

    @Test
    fun `pace saturation lightness regression anchor`() {
        val c = hslToArgb(0.0, 0.72, 0.55)
        assertEquals(223, red(c))
        assertEquals(58, green(c))
        assertEquals(58, blue(c))
        assertEquals(255, alpha(c))
    }
}
