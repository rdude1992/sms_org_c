package com.smsorganizer.app

import android.app.Service
import android.content.Intent
import android.os.IBinder

/**
 * Handles ACTION_RESPOND_VIA_MESSAGE (e.g. "decline call with text") without
 * opening the UI. Required for default-SMS-app eligibility.
 */
class HeadlessSmsSendService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val parsed = SmsUriParser.parse(intent)
        val address = parsed.address
        val body = parsed.body
        if (address.isNullOrBlank() || body.isNullOrBlank()) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        // Off the main thread: provider insert + radio call. "a;b" lists
        // send one message per recipient, as the stock messaging app does.
        Thread {
            for (recipient in address.split(';').map { it.trim() }.filter { it.isNotEmpty() }) {
                try {
                    SmsRepository.sendSms(applicationContext, recipient, body)
                } catch (_: Exception) {
                    // Best-effort: quick-reply failures shouldn't crash a background service.
                }
            }
            stopSelf(startId)
        }.start()
        return START_NOT_STICKY
    }
}
