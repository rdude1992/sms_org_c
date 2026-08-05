package com.smsorganizer.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Fires when this app is NOT the default SMS app. In that case the message
 * has already been written to content://sms by whichever app IS default,
 * so we don't insert anything — we just notify Flutter to refresh, if it's
 * running. This keeps the UI reasonably live even before the user grants
 * the default-app role.
 */
class SmsReceivedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (SmsRepository.isDefaultSmsApp(context)) return // SmsDeliverReceiver already handled it

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isEmpty()) return

        val address = messages[0].originatingAddress
        val timestamp = messages[0].timestampMillis
        val fullBody = messages.joinToString(separator = "") { it.messageBody ?: "" }

        MainActivity.eventSink?.success(
            mapOf(
                "id" to -1L, // not our row id — Dart should re-sync to get the real one
                "address" to address,
                "body" to fullBody,
                "date" to timestamp
            )
        )

        IncomingSmsNotifier.notify(context, address, fullBody)
    }
}
