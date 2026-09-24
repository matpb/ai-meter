package org.mat.pocketmeter.core

import java.time.ZoneId
import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Test

class ResetLabelTest {

    private val montreal = ZoneId.of("America/Montreal")

    @Test
    fun `same day reset formats as HH-mm`() {
        val now = ZonedDateTime.of(2026, 9, 23, 8, 0, 0, 0, montreal)
        val reset = ZonedDateTime.of(2026, 9, 23, 14, 32, 0, 0, montreal)

        val label = formatResetLabel(reset.toEpochSecond(), now.toEpochSecond(), montreal)

        assertEquals("14:32", label)
    }

    @Test
    fun `reset within 7 days but not same day formats as weekday HH-mm`() {
        // Wednesday now, reset the following Thursday morning.
        val now = ZonedDateTime.of(2026, 9, 23, 8, 0, 0, 0, montreal)
        val reset = ZonedDateTime.of(2026, 9, 24, 9, 0, 0, 0, montreal)

        val label = formatResetLabel(reset.toEpochSecond(), now.toEpochSecond(), montreal)

        assertEquals("Thu 09:00", label)
    }

    @Test
    fun `reset beyond 7 days falls back to month and day`() {
        val now = ZonedDateTime.of(2026, 9, 23, 8, 0, 0, 0, montreal)
        val reset = ZonedDateTime.of(2026, 10, 15, 9, 0, 0, 0, montreal)

        val label = formatResetLabel(reset.toEpochSecond(), now.toEpochSecond(), montreal)

        assertEquals("Oct 15", label)
    }
}
