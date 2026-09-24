package org.mat.aimeter.core

import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale

private val hhmm: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm", Locale.ENGLISH)

// Fallback for anything beyond the 7-day window (or in the past): month + day, unambiguous without a year.
private val monthDay: DateTimeFormatter = DateTimeFormatter.ofPattern("MMM d", Locale.ENGLISH)

fun formatResetLabel(resetAtEpochSeconds: Long, nowEpochSeconds: Long, zone: ZoneId): String {
    val reset = ZonedDateTime.ofInstant(Instant.ofEpochSecond(resetAtEpochSeconds), zone)
    val now = ZonedDateTime.ofInstant(Instant.ofEpochSecond(nowEpochSeconds), zone)

    if (reset.toLocalDate() == now.toLocalDate()) {
        return reset.format(hhmm)
    }

    val daysBetween = java.time.temporal.ChronoUnit.DAYS.between(now.toLocalDate(), reset.toLocalDate())
    if (daysBetween in 1..7) {
        val weekday = reset.dayOfWeek.getDisplayName(TextStyle.SHORT, Locale.ENGLISH)
        return "$weekday ${reset.format(hhmm)}"
    }

    return reset.format(monthDay)
}
