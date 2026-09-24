package org.mat.aimeter.core

import kotlinx.serialization.SerializationException

private val SUPPORTED_VERSIONS = setOf(1, 2)

sealed class IngestResult {
    data class Accept(val payload: Payload, val rawJson: String) : IngestResult()
    data class Reject(val reason: String) : IngestResult()
}

// FCM data messages can arrive out of order; drop anything older than what's already stored.
fun evaluateIngest(data: Map<String, String>, storedPayloadJson: String?): IngestResult {
    val raw = data["p"] ?: return IngestResult.Reject("missing p")

    val payload = try {
        parsePayload(raw)
    } catch (e: SerializationException) {
        return IngestResult.Reject("invalid json: ${e.message}")
    } catch (e: IllegalArgumentException) {
        return IngestResult.Reject("invalid json: ${e.message}")
    }

    if (payload.v !in SUPPORTED_VERSIONS) {
        return IngestResult.Reject("unsupported v ${payload.v}")
    }

    val stored = storedPayloadJson?.let { runCatching { parsePayload(it) }.getOrNull() }
    if (stored != null && payload.ts < stored.ts) {
        return IngestResult.Reject("older than stored payload")
    }

    return IngestResult.Accept(payload, raw)
}
