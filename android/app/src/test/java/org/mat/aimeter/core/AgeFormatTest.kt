package org.mat.aimeter.core

import org.junit.Assert.assertEquals
import org.junit.Test

class AgeFormatTest {

    @Test
    fun `under a minute formats as seconds`() {
        assertEquals("59s", formatAgeShort(59))
    }

    @Test
    fun `a minute formats as minutes`() {
        assertEquals("1m", formatAgeShort(60))
    }

    @Test
    fun `just under an hour formats as minutes`() {
        assertEquals("59m", formatAgeShort(3599))
    }

    @Test
    fun `an hour formats as hours`() {
        assertEquals("1h", formatAgeShort(3600))
    }

    @Test
    fun `just under a day formats as hours`() {
        assertEquals("23h", formatAgeShort(86399))
    }

    @Test
    fun `a day formats as days`() {
        assertEquals("1d", formatAgeShort(86400))
    }

    @Test
    fun `real bug report value floors to 5 days`() {
        assertEquals("5d", formatAgeShort(456205))
    }
}
