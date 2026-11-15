package com.smsorganizer.app

import android.content.Context

/**
 * Native-only storage for muted notification categories. Deliberately NOT
 * using the shared_preferences Flutter plugin's storage: that plugin
 * encodes list values with its own internal format, and this data must be
 * readable from plain Kotlin code running inside a BroadcastReceiver with
 * no Flutter engine alive (see IncomingSmsNotifier). Both the Settings UI
 * (via the MethodChannel) and the background receiver read/write this same
 * file directly, so they can never drift out of sync with each other.
 */
object NotificationPrefsRepository {
    private const val PREFS_NAME = "sms_organizer_notification_prefs"
    private const val KEY_MUTED = "muted_categories"
    private const val KEY_MUTED_THREADS = "muted_threads"

    /** Mute-until value meaning "until unmuted". */
    const val MUTE_FOREVER = Long.MAX_VALUE

    fun getMuted(context: Context): Set<String> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getStringSet(KEY_MUTED, emptySet()) ?: emptySet()
    }

    fun setMuted(context: Context, categories: Set<String>) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putStringSet(KEY_MUTED, categories).apply()
    }

    /**
     * Per-conversation mutes: thread id -> muted-until (epoch millis, or
     * [MUTE_FOREVER]). Read by IncomingSmsNotifier from a background receiver,
     * so, like the category mutes, they live in this native file rather than
     * in Dart storage. Expired entries count as unmuted and are dropped on
     * the next write, so a timed mute ends with no alarm or background job.
     */
    fun getThreadMutes(context: Context, now: Long = System.currentTimeMillis()): Map<Long, Long> =
        ThreadMutes.active(rawThreadMutes(context), now)

    fun isThreadMuted(context: Context, threadId: Long, now: Long = System.currentTimeMillis()): Boolean =
        ThreadMutes.isMuted(rawThreadMutes(context), threadId, now)

    /** [untilMillis] null unmutes the thread. */
    fun setThreadMute(context: Context, threadId: Long, untilMillis: Long?, now: Long = System.currentTimeMillis()) {
        val updated = ThreadMutes.withMute(rawThreadMutes(context), threadId, untilMillis, now)
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putStringSet(KEY_MUTED_THREADS, ThreadMutes.encode(updated)).apply()
    }

    private fun rawThreadMutes(context: Context): Map<Long, Long> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return ThreadMutes.decode(prefs.getStringSet(KEY_MUTED_THREADS, emptySet()) ?: emptySet())
    }
}

/** Pure encode/expiry logic for thread mutes, kept Android-free for JVM tests. */
object ThreadMutes {
    fun decode(raw: Set<String>): Map<Long, Long> = raw.mapNotNull { entry ->
        val sep = entry.indexOf(':')
        if (sep <= 0) return@mapNotNull null
        val id = entry.substring(0, sep).toLongOrNull() ?: return@mapNotNull null
        val until = entry.substring(sep + 1).toLongOrNull() ?: return@mapNotNull null
        id to until
    }.toMap()

    fun encode(mutes: Map<Long, Long>): Set<String> = mutes.map { (id, until) -> "$id:$until" }.toSet()

    fun active(mutes: Map<Long, Long>, now: Long): Map<Long, Long> = mutes.filterValues { it > now }

    fun isMuted(mutes: Map<Long, Long>, threadId: Long, now: Long): Boolean = (mutes[threadId] ?: 0L) > now

    fun withMute(mutes: Map<Long, Long>, threadId: Long, untilMillis: Long?, now: Long): Map<Long, Long> {
        val next = active(mutes, now).toMutableMap()
        if (untilMillis == null || untilMillis <= now) next.remove(threadId) else next[threadId] = untilMillis
        return next
    }
}
