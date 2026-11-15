package com.smsorganizer.app

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/**
 * App-level (non-SMS) notifications posted from Dart, e.g. budget alerts.
 * Kept separate from IncomingSmsNotifier so these never mix with message
 * notification grouping or the per-category SMS channels.
 */
object AppNotifier {
    private const val CHANNEL_BUDGETS = "app_budgets"

    // Distinct id range from SMS notifications, which use the thread id.
    private const val ID_BASE = 0x5B000000

    fun post(context: Context, tag: String, title: String, body: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return

        val manager = NotificationManagerCompat.from(context)
        manager.createNotificationChannel(
            NotificationChannelCompat.Builder(CHANNEL_BUDGETS, NotificationManagerCompat.IMPORTANCE_DEFAULT)
                .setName("Budgets")
                .setDescription("Alerts when a monthly spend budget reaches 80% or 100%")
                .build()
        )
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_BUDGETS)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        try {
            // One notification per tag (e.g. per category per month), replaced
            // when the same tag fires again (80% then 100%).
            manager.notify(tag, ID_BASE, notification)
        } catch (_: SecurityException) {
            // Permission revoked between the check and the call.
        }
    }
}
