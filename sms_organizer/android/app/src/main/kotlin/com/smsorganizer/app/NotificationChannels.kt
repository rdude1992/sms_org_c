package com.smsorganizer.app

import android.content.Context
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Creates one Android notification channel per SMS category, matching the
 * "sms_<category>" id scheme so the same channels apply whether the
 * notification is posted from a cold-start BroadcastReceiver or anywhere
 * else in the app. Also creates, on demand, one channel per conversation
 * (thread) — required alongside a notification's shortcut id for Android
 * to treat a thread as a "Conversation" (priority conversations, bubbles),
 * which a single per-category channel can't express on its own.
 *
 * Uses the AndroidX compat channel API throughout so this is a safe no-op
 * on API < 26 without needing Build.VERSION checks at most call sites.
 */
object NotificationChannels {
    private data class ChannelSpec(val key: String, val label: String, val importance: Int)

    private val specs = listOf(
        ChannelSpec("personal", "Personal messages", NotificationManagerCompat.IMPORTANCE_DEFAULT),
        ChannelSpec("promotional", "Promotions", NotificationManagerCompat.IMPORTANCE_DEFAULT),
        ChannelSpec("transactional", "Transactions", NotificationManagerCompat.IMPORTANCE_DEFAULT),
        ChannelSpec("otp", "OTP", NotificationManagerCompat.IMPORTANCE_HIGH),
        ChannelSpec("updates", "Updates", NotificationManagerCompat.IMPORTANCE_DEFAULT),
    )

    const val SUMMARY_CHANNEL_ID = "sms_summary"

    @Volatile
    private var created = false

    fun ensureCreated(context: Context) {
        if (created) return
        val manager = NotificationManagerCompat.from(context)
        for (spec in specs) {
            val channel = NotificationChannelCompat.Builder("sms_${spec.key}", spec.importance)
                .setName(spec.label)
                .setDescription("Notifications for ${spec.label.lowercase()} SMS")
                .build()
            manager.createNotificationChannel(channel)
        }
        val summary = NotificationChannelCompat.Builder(SUMMARY_CHANNEL_ID, NotificationManagerCompat.IMPORTANCE_LOW)
            .setName("Message summaries")
            .setDescription("Bundled summary shown when several new messages arrive at once")
            .build()
        manager.createNotificationChannel(summary)
        created = true
        // Categories muted in a previous session had their channel created
        // above at its normal spec importance — apply any already-muted
        // state on top so the OS's own settings screen doesn't show
        // "Alert" for a category the user muted before this process
        // started (e.g. after a fresh app relaunch).
        syncMuteState(context)
    }

    /**
     * Applies [NotificationPrefsRepository]'s mute state to the actual OS
     * channel importance for every category's parent channel — so system
     * Settings (reachable via the Settings screen's "tune" button)
     * reflects "Off" for a muted category instead of continuing to show
     * its normal importance ("Alert") like nothing changed.
     *
     * [IncomingSmsNotifier.notify] already fully suppresses posting a
     * notification for a muted category on its own — this isn't required
     * for muting to actually work, it exists purely so the OS's own
     * settings UI doesn't contradict what the app just did.
     *
     * Android has no in-place "change this channel's importance" call —
     * the only way is to delete and recreate the channel, which as a side
     * effect also clears anything the user customized for it (a
     * non-default sound, etc). That's an accepted trade-off: a plain
     * create-with-lower-importance call (no delete) can only ever *lower*
     * a channel's importance, never raise it back on unmute, so it can't
     * make the toggle work in both directions.
     */
    fun syncMuteState(context: Context) {
        val muted = NotificationPrefsRepository.getMuted(context)
        val manager = NotificationManagerCompat.from(context)
        for (spec in specs) {
            val channelId = "sms_${spec.key}"
            val targetImportance =
                if (muted.contains(spec.key)) NotificationManagerCompat.IMPORTANCE_NONE else spec.importance
            val current = manager.getNotificationChannelCompat(channelId)
            if (current != null && current.importance == targetImportance) continue
            manager.deleteNotificationChannel(channelId)
            val channel = NotificationChannelCompat.Builder(channelId, targetImportance)
                .setName(spec.label)
                .setDescription("Notifications for ${spec.label.lowercase()} SMS")
                .build()
            manager.createNotificationChannel(channel)
        }
    }

    /**
     * Per-conversation channel derived from the category's parent channel,
     * created lazily the first time a thread gets a notification and
     * reused afterwards (a cheap existence check, not a rebuild every
     * time). Falls back to the parent category channel id — pre-O, where
     * conversation channels don't exist as a concept, AND if creation
     * fails for any reason: a notification posted against a channel id
     * that doesn't exist gets silently dropped by Android (no exception,
     * nothing in the UI), which would be a much worse failure than simply
     * not getting the "Conversation" treatment. [parentId] is guaranteed
     * to already exist by the time this is called (see [ensureCreated]),
     * so it's always a safe value to fall back to.
     */
    fun ensureConversationChannel(
        context: Context,
        categoryKey: String,
        threadId: Long,
        displayName: String
    ): String {
        val parentId = "sms_$categoryKey"
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return parentId

        return try {
            val conversationId = "${parentId}_conv_$threadId"
            val manager = NotificationManagerCompat.from(context)
            if (manager.getNotificationChannelCompat(conversationId) == null) {
                val importance = specs.firstOrNull { it.key == categoryKey }?.importance
                    ?: NotificationManagerCompat.IMPORTANCE_DEFAULT
                val channel = NotificationChannelCompat.Builder(conversationId, importance)
                    .setName(displayName)
                    .setConversationId(parentId, threadId.toString())
                    .build()
                manager.createNotificationChannel(channel)
                // Some OEM builds accept the create call but never actually
                // materialise a channel with setConversationId() set — so
                // don't just trust the call succeeded, verify it before
                // handing back an id nothing will actually post against.
                if (manager.getNotificationChannelCompat(conversationId) == null) {
                    return parentId
                }
            }
            conversationId
        } catch (e: Exception) {
            Log.w("IncomingSmsNotif", "Conversation channel creation failed, using parent channel", e)
            parentId
        }
    }

    /**
     * The channel's real current importance as configured in system
     * settings — which the user may have changed directly there,
     * independent of this app's own mute toggle. Returns
     * IMPORTANCE_UNSPECIFIED if the channel doesn't exist yet (e.g. before
     * [ensureCreated] has ever run).
     */
    fun channelImportance(context: Context, channelId: String): Int {
        return NotificationManagerCompat.from(context)
            .getNotificationChannelCompat(channelId)
            ?.importance
            ?: NotificationManagerCompat.IMPORTANCE_UNSPECIFIED
    }
}
