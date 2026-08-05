package com.smsorganizer.app

import android.content.Context
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Creates one Android notification channel per SMS category, matching the
 * "sms_<category>" id scheme so the same channels apply whether the
 * notification is posted from a cold-start BroadcastReceiver or (in the
 * future) from anywhere else in the app. Uses the AndroidX compat channel
 * API so this is a safe no-op on API < 26 without needing a Build.VERSION
 * check here.
 */
object NotificationChannels {
    private data class ChannelSpec(val key: String, val label: String, val importance: Int)

    private val specs = listOf(
        ChannelSpec("personal", "Personal messages", NotificationManagerCompat.IMPORTANCE_DEFAULT),
        ChannelSpec("promotional", "Promotions", NotificationManagerCompat.IMPORTANCE_DEFAULT),
        ChannelSpec("transactional", "Transactions", NotificationManagerCompat.IMPORTANCE_DEFAULT),
        ChannelSpec("otp", "OTP", NotificationManagerCompat.IMPORTANCE_HIGH),
    )

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
        created = true
    }
}
