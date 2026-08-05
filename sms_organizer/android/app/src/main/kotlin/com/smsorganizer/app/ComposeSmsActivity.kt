package com.smsorganizer.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Required so this app can be the target of sms:/smsto:/mms:/mmsto: intents
 * from other apps (e.g. tapping a phone number and choosing "Send message").
 * It has no UI of its own — it just forwards the recipient/body into
 * MainActivity, which routes to the Flutter compose screen on launch.
 */
class ComposeSmsActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val address = intent?.data?.schemeSpecificPart
        val body = intent?.getStringExtra(Intent.EXTRA_TEXT)

        val forward = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            putExtra("compose_address", address)
            putExtra("compose_body", body)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        startActivity(forward)
        finish()
    }
}
