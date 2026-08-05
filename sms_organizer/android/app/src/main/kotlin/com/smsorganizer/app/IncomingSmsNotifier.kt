package com.smsorganizer.app

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Telephony
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/**
 * Shared entry point called by both SmsDeliverReceiver (app is default) and
 * SmsReceivedReceiver (app is not yet default) to post a notification for
 * an incoming SMS.
 *
 * This is the fix for the background-delivery gap: everything here runs in
 * plain Kotlin — categorisation, the mute check, contact-name lookup, and
 * the actual NotificationCompat call — with zero dependency on a running
 * Flutter engine or Dart VM. Android guarantees SmsDeliverReceiver fires
 * regardless of whether the app's process is alive, so as long as this
 * function doesn't itself need Dart, the notification is reliable even
 * when Android has fully killed the app.
 */
object IncomingSmsNotifier {

    fun notify(context: Context, address: String?, body: String?) {
        if (address.isNullOrEmpty() || body.isNullOrEmpty()) return
        if (!hasNotificationPermission(context)) return

        val category = Categorizer.categorize(body)
        val muted = NotificationPrefsRepository.getMuted(context)
        if (muted.contains(category.prefKey)) return

        NotificationChannels.ensureCreated(context)

        val threadId = Telephony.Threads.getOrCreateThreadId(context, address)
        val displayName = ContactsRepository.lookupDisplayName(context, address) ?: address

        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("notification_thread_id", threadId)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            threadId.toInt(),
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, "sms_${category.prefKey}")
            // TODO: swap for a dedicated monochrome status-bar icon before
            // release — the launcher icon works but won't render cleanly
            // silhouetted in the status bar the way a proper notification
            // icon (white glyph, transparent background) would.
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(displayName)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(
                if (category == Categorizer.Category.OTP) NotificationCompat.PRIORITY_HIGH
                else NotificationCompat.PRIORITY_DEFAULT
            )
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(threadId.toInt(), notification)
        } catch (_: SecurityException) {
            // Permission was revoked between the check above and this call
            // (e.g. user turned it off in Settings mid-broadcast) — the
            // message is still safely in content://sms either way.
        }
    }

    private fun hasNotificationPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    }
}
