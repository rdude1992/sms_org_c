package com.smsorganizer.app

import android.content.Context

/**
 * Native-only storage for muted notification categories. Deliberately NOT
 * using the shared_preferences Flutter plugin's storage: that plugin
 * encodes list values with its own internal format, and this data must be
 * readable from plain Kotlin code running inside a BroadcastReceiver with
 * no Flutter engine alive (see IncomingSmsNotifier). Both the Settings UI
 * (via the MethodChannel) and the background receiver read/write this same
 * file directly, so they can never drift out of sync with each other.
 */
object NotificationPrefsRepository {
    private const val PREFS_NAME = "sms_organizer_notification_prefs"
    private const val KEY_MUTED = "muted_categories"

    fun getMuted(context: Context): Set<String> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getStringSet(KEY_MUTED, emptySet()) ?: emptySet()
    }

    fun setMuted(context: Context, categories: Set<String>) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putStringSet(KEY_MUTED, categories).apply()
    }
}
