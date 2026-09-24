package org.mat.aimeter.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Payload(
    val v: Int,
    val ts: Long,
    val meters: List<Meter>,
)

@Serializable
data class Meter(
    val id: String,
    val type: String? = null,
    val label: String,
    val sub: String? = null,
    val ok: Boolean,
    val source: String? = null,
    val age: Long? = null,
    val plan: String? = null,
    val reason: String? = null,
    val bars: List<Bar> = emptyList(),
)

@Serializable
data class Bar(
    val k: String,
    val label: String? = null,
    val pct: Int = 0,
    @SerialName("reset_at") val resetAt: Long = 0,
    val fresh: Boolean = false,
    val win: Int? = null,
)

// v1 payloads have no bar label; fall back to k.
val Bar.displayLabel: String get() = label ?: k
