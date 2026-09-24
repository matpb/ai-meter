package org.mat.pocketmeter.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

private fun payloadJson(ts: Long, v: Int = 2): String =
    """{"v":$v,"ts":$ts,"meters":[]}"""

class PayloadIngestTest {

    @Test
    fun `rejects missing p`() {
        val result = evaluateIngest(emptyMap(), null)
        assertTrue(result is IngestResult.Reject)
    }

    @Test
    fun `rejects invalid json`() {
        val result = evaluateIngest(mapOf("p" to "not json"), null)
        assertTrue(result is IngestResult.Reject)
    }

    @Test
    fun `rejects unsupported version`() {
        val result = evaluateIngest(mapOf("p" to payloadJson(ts = 100, v = 99)), null)
        assertTrue(result is IngestResult.Reject)
    }

    @Test
    fun `rejects payload older than stored`() {
        val stored = payloadJson(ts = 200)
        val incoming = payloadJson(ts = 100)
        val result = evaluateIngest(mapOf("p" to incoming), stored)
        assertTrue(result is IngestResult.Reject)
    }

    @Test
    fun `accepts payload with equal ts to stored`() {
        val stored = payloadJson(ts = 200)
        val incoming = payloadJson(ts = 200)
        val result = evaluateIngest(mapOf("p" to incoming), stored)
        assertTrue(result is IngestResult.Accept)
        assertEquals(200L, (result as IngestResult.Accept).payload.ts)
    }

    @Test
    fun `accepts payload newer than stored`() {
        val stored = payloadJson(ts = 200)
        val incoming = payloadJson(ts = 300)
        val result = evaluateIngest(mapOf("p" to incoming), stored)
        assertTrue(result is IngestResult.Accept)
    }

    @Test
    fun `accepts first payload when nothing stored yet`() {
        val result = evaluateIngest(mapOf("p" to payloadJson(ts = 100)), null)
        assertTrue(result is IngestResult.Accept)
    }

    @Test
    fun `accepts v1 payload`() {
        val result = evaluateIngest(mapOf("p" to payloadJson(ts = 100, v = 1)), null)
        assertTrue(result is IngestResult.Accept)
    }

    @Test
    fun `accepts payload with a null pct and reset_at bar`() {
        val incoming = """
        {"v":2,"ts":100,"meters":[
         {"id":"claude-1","label":"Claude","sub":null,"ok":true,"bars":[{"k":"5h","pct":null,"reset_at":null}]}
        ]}
        """
        val result = evaluateIngest(mapOf("p" to incoming), null)
        assertTrue(result is IngestResult.Accept)
        val bar = (result as IngestResult.Accept).payload.meters.first().bars.first()
        assertEquals(0, bar.pct)
        assertEquals(0L, bar.resetAt)
    }
}
