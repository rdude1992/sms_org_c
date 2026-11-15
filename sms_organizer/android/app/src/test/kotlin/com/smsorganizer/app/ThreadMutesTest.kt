package com.smsorganizer.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ThreadMutesTest {
    private val now = 1_000_000L

    @Test
    fun timedMuteExpires() {
        val mutes = ThreadMutes.withMute(emptyMap(), 7L, now + 100, now)
        assertTrue(ThreadMutes.isMuted(mutes, 7L, now + 99))
        assertFalse(ThreadMutes.isMuted(mutes, 7L, now + 100))
    }

    @Test
    fun foreverMuteNeverExpires() {
        val mutes = ThreadMutes.withMute(emptyMap(), 7L, NotificationPrefsRepository.MUTE_FOREVER, now)
        assertTrue(ThreadMutes.isMuted(mutes, 7L, Long.MAX_VALUE - 1))
    }

    @Test
    fun nullUnmutesAndExpiredEntriesArePrunedOnWrite() {
        var mutes = ThreadMutes.withMute(emptyMap(), 1L, now + 10, now)
        mutes = ThreadMutes.withMute(mutes, 2L, NotificationPrefsRepository.MUTE_FOREVER, now)
        mutes = ThreadMutes.withMute(mutes, 2L, null, now + 20) // unmute 2; 1 has expired by now+20
        assertEquals(emptyMap<Long, Long>(), mutes)
    }

    @Test
    fun encodeDecodeRoundTripsAndSkipsGarbage() {
        val mutes = mapOf(5L to 123L, 9L to NotificationPrefsRepository.MUTE_FOREVER)
        val raw = ThreadMutes.encode(mutes) + setOf("bad", ":1", "x:y")
        assertEquals(mutes, ThreadMutes.decode(raw))
    }

    @Test
    fun unmutedThreadIsNotMuted() {
        assertFalse(ThreadMutes.isMuted(emptyMap(), 3L, now))
    }
}
