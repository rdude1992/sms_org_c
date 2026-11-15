package com.smsorganizer.app

import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput

/**
 * Handles the quick actions attached to an incoming-SMS notification (see
 * IncomingSmsNotifier) — inline reply, mark as read, and copy OTP — none
 * of which need to open the app. One receiver for all three (rather than
 * one each) since they're small and closely related: "act on this
 * thread's notification in the background."
 *
 * Not exported — only ever fired by PendingIntents this app itself created.
 */
class NotificationActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_REPLY = "com.smsorganizer.app.action.REPLY"
        const val ACTION_MARK_READ = "com.smsorganizer.app.action.MARK_READ"
        const val ACTION_COPY_OTP = "com.smsorganizer.app.action.COPY_OTP"
        const val ACTION_DELETE = "com.smsorganizer.app.action.DELETE"

        const val EXTRA_THREAD_ID = "thread_id"
        const val EXTRA_ADDRESS = "address"
        const val EXTRA_OTP_CODE = "otp_code"
        const val EXTRA_SUBSCRIPTION_ID = "subscription_id"
        const val KEY_REPLY_TEXT = "key_reply_text"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val threadId = intent.getLongExtra(EXTRA_THREAD_ID, -1L)
        if (threadId == -1L) return

        if (intent.action == ACTION_COPY_OTP) {
            // Clipboard writes are cheap and must not wait behind a queued send.
            handleCopyOtp(context, intent)
            return
        }
        // Reply/mark-read/delete hit the SMS provider (and the radio), so
        // keep them off the main thread — see ReceiverAsync.kt.
        val appContext = context.applicationContext
        runAsync("NotificationAction") {
            when (intent.action) {
                ACTION_REPLY -> handleReply(appContext, intent, threadId)
                ACTION_MARK_READ -> handleMarkRead(appContext, threadId)
                ACTION_DELETE -> handleDelete(appContext, threadId)
            }
            // Keep a running app's list in sync with what the action changed.
            MainActivity.emitEvent(mapOf("type" to "changed", "threadId" to threadId))
        }
    }

    private fun handleReply(context: Context, intent: Intent, threadId: Long) {
        val address = intent.getStringExtra(EXTRA_ADDRESS) ?: return
        val replyText = RemoteInput.getResultsFromIntent(intent)
            ?.getCharSequence(KEY_REPLY_TEXT)
            ?.toString()
            ?.trim()
        if (replyText.isNullOrEmpty()) return

        // Reply from the SIM that received the message, not the device default.
        val subscriptionId = intent.getIntExtra(EXTRA_SUBSCRIPTION_ID, -1)
        try {
            SmsRepository.sendSms(context, address, replyText, subscriptionId.takeIf { it >= 0 })
        } catch (_: Exception) {
            // Sending failed (no signal, SmsManager error, etc.) — leave the
            // notification as-is rather than falsely showing the reply as
            // sent; the user can still open the app and retry from there.
            return
        }
        IncomingSmsNotifier.notifyAfterReply(context, threadId, address, replyText, subscriptionId)
    }

    private fun handleMarkRead(context: Context, threadId: Long) {
        val ids = SmsRepository.getUnreadIncomingIds(context, threadId)
        if (ids.isNotEmpty()) {
            SmsRepository.markRead(context, ids, true)
        }
        ConversationHistoryStore.clear(context, threadId)
        NotificationManagerCompat.from(context).cancel(threadId.toInt())
    }

    /**
     * Deletes the unread incoming messages this notification represents
     * straight from content://sms — same id scope as [handleMarkRead], so
     * it never reaches back past what's actually shown in the notification.
     */
    private fun handleDelete(context: Context, threadId: Long) {
        val ids = SmsRepository.getUnreadIncomingIds(context, threadId)
        if (ids.isNotEmpty()) {
            SmsRepository.deleteMessages(context, ids)
        }
        ConversationHistoryStore.clear(context, threadId)
        NotificationManagerCompat.from(context).cancel(threadId.toInt())
    }

    private fun handleCopyOtp(context: Context, intent: Intent) {
        val code = intent.getStringExtra(EXTRA_OTP_CODE) ?: return
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("OTP", code))
    }
}
