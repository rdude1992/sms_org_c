package com.smsorganizer.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Fires only when this app is set as the DEFAULT SMS app. The system does
 * NOT write the message into content://sms for us in this case — we must
 * do it ourselves, then notify the running Flutter UI (if any) so the
 * conversation list updates live instead of waiting for the next full sync.
 */
class SmsDeliverReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_DELIVER_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isEmpty()) return

        val address = messages[0].originatingAddress
        val timestamp = messages[0].timestampMillis
        val fullBody = messages.joinToString(separator = "") { it.messageBody ?: "" }
        // AOSP's telephony framework stamps incoming SMS_DELIVER/SMS_RECEIVED
        // intents with the receiving SIM's subscription id under this extra
        // on dual-SIM devices (API 22+). Absent on single-SIM devices.
        val subscriptionId = intent.getIntExtra("subscription", -1)

        val id = SmsRepository.insertIncoming(context, address, fullBody, timestamp, subscriptionId)

        MainActivity.eventSink?.success(
            mapOf(
                "id" to id,
                "address" to address,
                "body" to fullBody,
                "date" to timestamp
            )
        )

        // Runs entirely natively — works even if this receiver fired with
        // no Flutter engine alive to receive the event above.
        IncomingSmsNotifier.notify(context, address, fullBody)
    }
}
