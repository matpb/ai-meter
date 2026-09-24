package org.mat.aimeter.core

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HasNoResetInfoTest {

    @Test
    fun `resetAt equal to payload ts has no reset info`() {
        assertTrue(hasNoResetInfo(1000L, 1000L))
    }

    @Test
    fun `resetAt before payload ts has no reset info`() {
        assertTrue(hasNoResetInfo(500L, 1000L))
    }

    @Test
    fun `resetAt after payload ts has reset info`() {
        assertFalse(hasNoResetInfo(1500L, 1000L))
    }
}
