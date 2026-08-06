package com.smsorganizer.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import androidx.core.content.ContextCompat

/**
 * Dual-SIM support: maps subscription ids (what the SMS provider and
 * SmsManager deal in) to the 0-based slot index the user actually sees
 * ("SIM 1" / "SIM 2"), and lists the currently active SIMs for the compose
 * screen's SIM picker.
 *
 * All of this requires READ_PHONE_STATE, which is a separate runtime grant
 * from the SMS permission group — every function here degrades to "unknown"
 * rather than throwing if it's not held, since a single-SIM phone or a user
 * who declined the permission should still be able to send/receive SMS.
 */
object SimRepository {

    fun hasPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_PHONE_STATE
        ) == PackageManager.PERMISSION_GRANTED

    /** Active SIMs as maps of subscriptionId/slotIndex/displayName/carrierName. */
    fun getActiveSims(context: Context): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP_MR1 || !hasPermission(context)) {
            return emptyList()
        }
        return try {
            val subscriptionManager =
                context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
            val infos = subscriptionManager.activeSubscriptionInfoList ?: return emptyList()
            infos.map { info ->
                mapOf(
                    "subscriptionId" to info.subscriptionId,
                    "slotIndex" to info.simSlotIndex,
                    "displayName" to (info.displayName?.toString() ?: "SIM ${info.simSlotIndex + 1}"),
                    "carrierName" to info.carrierName?.toString()
                )
            }
        } catch (_: SecurityException) {
            emptyList()
        }
    }

    /**
     * Builds a subscriptionId -> slotIndex lookup once per call site (rather
     * than one binder call per message row) for tagging content://sms rows
     * with which physical SIM they belong to.
     */
    fun subscriptionToSlotMap(context: Context): Map<Int, Int> =
        getActiveSims(context).associate {
            (it["subscriptionId"] as Int) to (it["slotIndex"] as Int)
        }

    /** [subscriptionId] null/negative (no SIM chosen, or a single-SIM device) falls back to the default SmsManager. */
    fun smsManagerFor(context: Context, subscriptionId: Int?): SmsManager {
        val default = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }
        if (subscriptionId == null || subscriptionId < 0) return default
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
            } else {
                default
            }
        } catch (_: Exception) {
            default
        }
    }
}
