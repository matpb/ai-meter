package org.mat.pocketmeter.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private const val SAMPLE_PAYLOAD = """
{"v":1,"ts":1790200000,"meters":[
 {"id":"claude-personal","label":"Claude","sub":"personal","ok":true,"source":"token","age":0,"plan":null,"bars":[{"k":"5h","pct":5,"reset_at":1790217277,"fresh":false},{"k":"7d","pct":40,"reset_at":1790434477,"fresh":false},{"k":"Fable","pct":42,"reset_at":1790434477,"fresh":false}]},
 {"id":"claude-work","label":"Claude","sub":"work","ok":true,"source":"token","age":0,"plan":null,"bars":[{"k":"5h","pct":4,"reset_at":1790212464,"fresh":false},{"k":"7d","pct":29,"reset_at":1790560464,"fresh":false}]},
 {"id":"codex","label":"Codex","sub":null,"ok":true,"source":"live","age":0,"plan":"plus","bars":[{"k":"5h","pct":0,"reset_at":1790218001,"fresh":true},{"k":"7d","pct":0,"reset_at":1790804801,"fresh":true}]},
 {"id":"grok","label":"Grok","sub":null,"ok":false,"reason":"token expired","bars":[]},
 {"id":"cursor","label":"Cursor","sub":null,"ok":true,"source":"live","age":0,"plan":"Pro","bars":[{"k":"Models","pct":1,"reset_at":1792099994,"fresh":false},{"k":"Grok","pct":13,"reset_at":1790741450,"fresh":false}]}
]}
"""

private const val SAMPLE_PAYLOAD_V2 = """
{"v":2,"ts":1790270278,"meters":[
 {"id":"claude-1","type":"claude","label":"Claude","sub":"Personal","ok":true,"source":"token","age":0,"plan":null,"reason":null,"bars":[{"k":"5h","label":"5h","pct":9,"reset_at":1790282399,"fresh":false,"win":18000}]},
 {"id":"grok-1","type":"grok","label":"Grok","sub":null,"ok":false,"source":null,"age":null,"plan":null,"reason":"token expired","bars":[]}
]}
"""

class PayloadParserTest {

    @Test
    fun `parses full sample payload`() {
        val payload = parsePayload(SAMPLE_PAYLOAD)

        assertEquals(1, payload.v)
        assertEquals(1790200000L, payload.ts)
        assertEquals(5, payload.meters.size)
    }

    @Test
    fun `grok meter with ok false parses without throwing`() {
        val payload = parsePayload(SAMPLE_PAYLOAD)
        val grok = payload.meters.first { it.id == "grok" }

        assertFalse(grok.ok)
        assertEquals("token expired", grok.reason)
        assertTrue(grok.bars.isEmpty())
        assertNull(grok.source)
        assertNull(grok.age)
        assertNull(grok.plan)
    }

    @Test
    fun `codex meter has a fresh bar with pct 0`() {
        val payload = parsePayload(SAMPLE_PAYLOAD)
        val codex = payload.meters.first { it.id == "codex" }

        assertEquals("plus", codex.plan)
        val fiveHour = codex.bars.first { it.k == "5h" }
        assertTrue(fiveHour.fresh)
        assertEquals(0, fiveHour.pct)
    }

    @Test
    fun `claude-personal meter has three bars`() {
        val payload = parsePayload(SAMPLE_PAYLOAD)
        val claudePersonal = payload.meters.first { it.id == "claude-personal" }

        assertEquals("personal", claudePersonal.sub)
        assertEquals(3, claudePersonal.bars.size)
        assertEquals(5, claudePersonal.bars[0].pct)
        assertEquals("5h", claudePersonal.bars[0].k)
        assertEquals(40, claudePersonal.bars[1].pct)
        assertEquals("7d", claudePersonal.bars[1].k)
        assertEquals(42, claudePersonal.bars[2].pct)
        assertEquals("Fable", claudePersonal.bars[2].k)
    }

    @Test
    fun `v1 bar has no label and falls back to k`() {
        val payload = parsePayload(SAMPLE_PAYLOAD)
        val bar = payload.meters.first { it.id == "claude-personal" }.bars[0]

        assertNull(bar.label)
        assertEquals("5h", bar.displayLabel)
    }

    @Test
    fun `v2 payload parses type, bar label, reason and null sub`() {
        val payload = parsePayload(SAMPLE_PAYLOAD_V2)

        assertEquals(2, payload.v)
        val claude = payload.meters.first { it.id == "claude-1" }
        assertEquals("claude", claude.type)
        assertEquals("Personal", claude.sub)
        assertEquals("5h", claude.bars[0].label)
        assertEquals("5h", claude.bars[0].displayLabel)

        val grok = payload.meters.first { it.id == "grok-1" }
        assertEquals("grok", grok.type)
        assertNull(grok.sub)
        assertFalse(grok.ok)
        assertEquals("token expired", grok.reason)
    }

    @Test
    fun `bar with null pct and reset_at parses with defaults`() {
        val payloadJson = """
        {"v":2,"ts":1790270278,"meters":[
         {"id":"claude-1","type":"claude","label":"Claude","sub":null,"ok":true,"bars":[{"k":"5h","pct":null,"reset_at":null}]}
        ]}
        """
        val payload = parsePayload(payloadJson)
        val bar = payload.meters.first().bars.first()

        assertEquals(0, bar.pct)
        assertEquals(0L, bar.resetAt)
        assertFalse(bar.fresh)
    }
}
