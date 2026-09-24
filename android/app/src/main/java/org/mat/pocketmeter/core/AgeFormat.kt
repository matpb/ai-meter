package org.mat.pocketmeter.core

// Humanizes a stale age in seconds; matches desktop QML's fmtAge (floor division).
fun formatAgeShort(ageSeconds: Long): String = when {
    ageSeconds < 60 -> "${ageSeconds}s"
    ageSeconds < 3600 -> "${ageSeconds / 60}m"
    ageSeconds < 86400 -> "${ageSeconds / 3600}h"
    else -> "${ageSeconds / 86400}d"
}
