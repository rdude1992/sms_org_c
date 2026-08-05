package com.smsorganizer.app

import android.content.Context
import android.net.Uri
import android.provider.ContactsContract

/**
 * Reads the full contacts list once so the Dart side can build a
 * number-normalised lookup map, rather than doing one binder call per SMS
 * sender (which would be slow for a large inbox).
 */
object ContactsRepository {
    fun getAllContacts(context: Context): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
            ContactsContract.CommonDataKinds.Phone.NUMBER
        )
        val cursor = context.contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            projection,
            null,
            null,
            null
        )
        cursor?.use {
            val nameIdx = it.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
            val numberIdx = it.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.NUMBER)
            while (it.moveToNext()) {
                results.add(
                    mapOf(
                        "name" to it.getString(nameIdx),
                        "number" to it.getString(numberIdx)
                    )
                )
            }
        }
        return results
    }

    /**
     * Single-number reverse lookup, used by IncomingSmsNotifier when
     * posting a notification. Deliberately a targeted PhoneLookup query
     * rather than loading all contacts — this runs inside a
     * BroadcastReceiver's short execution window, where a bulk query for
     * one notification would be wasteful and, on a large contacts list,
     * risks exceeding the receiver's time budget.
     */
    fun lookupDisplayName(context: Context, number: String): String? {
        return try {
            val uri = Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                Uri.encode(number)
            )
            val cursor = context.contentResolver.query(
                uri,
                arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                null,
                null,
                null
            )
            cursor?.use {
                if (it.moveToFirst()) {
                    it.getString(it.getColumnIndexOrThrow(ContactsContract.PhoneLookup.DISPLAY_NAME))
                } else {
                    null
                }
            }
        } catch (_: Exception) {
            // Missing permission, malformed number (e.g. a short alphanumeric
            // sender ID like "HDFCBK" that PhoneLookup can't match), etc. —
            // fall back to showing the raw address, same as the Dart side.
            null
        }
    }
}

