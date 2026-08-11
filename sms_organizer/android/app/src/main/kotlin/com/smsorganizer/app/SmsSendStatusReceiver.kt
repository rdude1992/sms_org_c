package com.smsorganizer.app

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Fires once per SMS part for both the "handed to the radio" (SENT) and
 * "reached the handset" (DELIVERED) reports SmsRepository.sendSms requests
 * via per-part PendingIntents — see SmsManager.sendMultipartTextMessage's
 * sentIntents/deliveryIntents params. A message split into N parts
 * (SmsManager.divideMessage) fires N callbacks per phase; [PartTracker]
 * waits for all of them before deciding the whole message's outcome, so a
 * 2-part SMS where only one part fails is reported failed rather than
 * flip-flopping the row as each part reports in separately.
 *
 * Tracking state is in-memory only, keyed by the row's content://sms id —
 * acceptable because both callbacks for a given part normally land within
 * moments of each other while the process that issued the send is still
 * alive; if the process dies in between (rare), the affected row simply
 * stops updating rather than crashing anything, no worse off than having no
 * delivery tracking at all. Many carriers/SMSCs also never send a delivery
 * report regardless of what's requested — in that case the row just never
 * leaves STATUS_PENDING, which SmsMessage.sendState reads as "Sent" rather
 * than "Delivered". That's correct real-world behaviour, not a bug.
 *
 * Not exported — only ever fired by PendingIntents this app itself created.
 */
class SmsSendStatusReceiver : BroadcastReceiver() {

    private class PartTracker(total: Int) {
        val remaining = AtomicInteger(total)
        val anyFailed = AtomicBoolean(false)
    }

    companion object {
        private const val ACTION_SMS_SENT = "com.smsorganizer.app.action.SMS_SENT"
        private const val ACTION_SMS_DELIVERED = "com.smsorganizer.app.action.SMS_DELIVERED"
        private const val EXTRA_ROW_ID = "row_id"

        private val sentTrackers = ConcurrentHashMap<Long, PartTracker>()
        private val deliveredTrackers = ConcurrentHashMap<Long, PartTracker>()

        /** Called by SmsRepository.sendSms before dispatching, so callbacks that arrive have somewhere to aggregate. */
        fun beginTracking(rowId: Long, partCount: Int) {
            sentTrackers[rowId] = PartTracker(partCount)
            deliveredTrackers[rowId] = PartTracker(partCount)
        }

        fun sentPendingIntent(context: Context, rowId: Long, partIndex: Int): PendingIntent =
            pendingIntent(context, ACTION_SMS_SENT, rowId, partIndex, delivered = false)

        fun deliveredPendingIntent(context: Context, rowId: Long, partIndex: Int): PendingIntent =
            pendingIntent(context, ACTION_SMS_DELIVERED, rowId, partIndex, delivered = true)

        private fun pendingIntent(
            context: Context,
            action: String,
            rowId: Long,
            partIndex: Int,
            delivered: Boolean
        ): PendingIntent {
            val intent = Intent(context, SmsSendStatusReceiver::class.java).apply {
                this.action = action
                putExtra(EXTRA_ROW_ID, rowId)
            }
            // Distinct per (row, part, phase) so the system doesn't collapse
            // different parts'/phases' callbacks into a single PendingIntent
            // — rowId alone can exceed Int range over a long-lived provider,
            // so it's folded down rather than used directly as the code.
            var requestCode = rowId.hashCode()
            requestCode = requestCode * 31 + partIndex
            requestCode = requestCode * 31 + if (delivered) 1 else 0
            return PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val rowId = intent.getLongExtra(EXTRA_ROW_ID, -1L)
        if (rowId == -1L) return
        // For SMS_SENT: RESULT_OK, or one of SmsManager's RESULT_ERROR_*
        // constants. For SMS_DELIVERED: RESULT_OK (delivered) or
        // RESULT_CANCELED (not delivered). Readable here even though this
        // receiver is manifest-registered rather than dynamically
        // registered for an ordered broadcast, because the telephony
        // framework delivers these specific reports via
        // PendingIntent.send(context, resultCode, intent).
        val partSucceeded = resultCode == Activity.RESULT_OK

        when (intent.action) {
            ACTION_SMS_SENT -> onPartReported(sentTrackers, rowId, partSucceeded) { allSucceeded ->
                SmsRepository.markSentResult(context, rowId, allSucceeded)
                MainActivity.eventSink?.success(mapOf("type" to "sendStatus", "id" to rowId))
            }
            ACTION_SMS_DELIVERED -> onPartReported(deliveredTrackers, rowId, partSucceeded) { allDelivered ->
                SmsRepository.markDeliveryResult(context, rowId, allDelivered)
                MainActivity.eventSink?.success(mapOf("type" to "sendStatus", "id" to rowId))
            }
        }
    }

    private fun onPartReported(
        trackers: ConcurrentHashMap<Long, PartTracker>,
        rowId: Long,
        partSucceeded: Boolean,
        onAllReported: (allSucceeded: Boolean) -> Unit
    ) {
        // Falls back to a fresh single-part tracker if beginTracking's entry
        // is missing (process was killed and restarted between parts, or
        // this callback raced ahead of it) — best-effort rather than
        // dropping the report on the floor, per the class-level comment.
        val tracker = trackers.getOrPut(rowId) { PartTracker(1) }
        if (!partSucceeded) tracker.anyFailed.set(true)
        if (tracker.remaining.decrementAndGet() <= 0) {
            trackers.remove(rowId)
            onAllReported(!tracker.anyFailed.get())
        }
    }
}
