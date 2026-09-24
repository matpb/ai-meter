package org.mat.pocketmeter.core

import kotlinx.serialization.json.Json

private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }

fun parsePayload(json_: String): Payload = json.decodeFromString(Payload.serializer(), json_)
