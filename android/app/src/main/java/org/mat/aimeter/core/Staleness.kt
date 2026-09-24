package org.mat.aimeter.core

private const val PAYLOAD_STALE_SECONDS = 1800L
private const val METER_STALE_SECONDS = 3600L

fun isPayloadStale(ts: Long, now: Long): Boolean = now - ts > PAYLOAD_STALE_SECONDS

fun isMeterStale(age: Long?): Boolean = age != null && age > METER_STALE_SECONDS
