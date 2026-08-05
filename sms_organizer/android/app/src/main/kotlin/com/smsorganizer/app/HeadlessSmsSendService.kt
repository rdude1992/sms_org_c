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
        val address = intent?.data?.schemeSpecificPart
        val body = intent?.getStringExtra(Intent.EXTRA_TEXT)
        if (address != null && body != null) {
            try {
                SmsRepository.sendSms(this, address, body)
            } catch (_: Exception) {
                // Best-effort: quick-reply failures shouldn't crash a background service.
            }
        }
        stopSelf()
        return START_NOT_STICKY
    }
}
