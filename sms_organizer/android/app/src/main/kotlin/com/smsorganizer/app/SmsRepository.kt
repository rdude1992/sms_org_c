package com.smsorganizer.app

import android.app.role.RoleManager
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.Telephony
import android.telephony.SmsManager

/**
 * Thin wrapper around the platform SMS ContentProvider (content://sms).
 * Kept free of Flutter types so it can be called from both MainActivity
 * (foreground, MethodChannel) and the broadcast receivers (background).
 */
object SmsRepository {

    fun isDefaultSmsApp(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = context.getSystemService(Context.ROLE_SERVICE) as RoleManager
            roleManager.isRoleHeld(RoleManager.ROLE_SMS)
        } else {
            Telephony.Sms.getDefaultSmsPackage(context) == context.packageName
        }
    }

    /**
     * Reads every row from content://sms (inbox + sent + draft + outbox).
     * Categorisation and thread-grouping happen on the Dart side; this just
     * returns raw rows as maps so we don't duplicate business logic natively.
     */
    fun getAllMessages(context: Context): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            Telephony.Sms._ID,
            Telephony.Sms.THREAD_ID,
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE,
            Telephony.Sms.DATE_SENT,
            Telephony.Sms.TYPE, // 1=inbox, 2=sent, 3=draft, 4=outbox, 5=failed, 6=queued
            Telephony.Sms.READ,
            Telephony.Sms.SEEN
        )
        val cursor = context.contentResolver.query(
            Telephony.Sms.CONTENT_URI, projection, null, null,
            "${Telephony.Sms.DATE} DESC"
        )
        cursor?.use {
            while (it.moveToNext()) {
                results.add(
                    mapOf(
                        "id" to it.getLong(it.getColumnIndexOrThrow(Telephony.Sms._ID)),
                        "threadId" to it.getLong(it.getColumnIndexOrThrow(Telephony.Sms.THREAD_ID)),
                        "address" to it.getString(it.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)),
                        "body" to it.getString(it.getColumnIndexOrThrow(Telephony.Sms.BODY)),
                        "date" to it.getLong(it.getColumnIndexOrThrow(Telephony.Sms.DATE)),
                        "dateSent" to it.getLong(it.getColumnIndexOrThrow(Telephony.Sms.DATE_SENT)),
                        "type" to it.getInt(it.getColumnIndexOrThrow(Telephony.Sms.TYPE)),
                        "read" to (it.getInt(it.getColumnIndexOrThrow(Telephony.Sms.READ)) == 1),
                        "seen" to (it.getInt(it.getColumnIndexOrThrow(Telephony.Sms.SEEN)) == 1)
                    )
                )
            }
        }
        return results
    }

    /**
     * Sends an SMS and, since a default SMS app is responsible for its own
     * "Sent" record (the system does not insert it automatically), writes the
     * sent message into content://sms/sent ourselves.
     */
    fun sendSms(context: Context, address: String, body: String) {
        val smsManager: SmsManager =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }

        val parts = smsManager.divideMessage(body)
        smsManager.sendMultipartTextMessage(address, null, parts, null, null)

        val values = ContentValues().apply {
            put(Telephony.Sms.ADDRESS, address)
            put(Telephony.Sms.BODY, body)
            put(Telephony.Sms.DATE, System.currentTimeMillis())
            put(Telephony.Sms.READ, 1)
            put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_SENT)
        }
        context.contentResolver.insert(Telephony.Sms.Sent.CONTENT_URI, values)
    }

    /** Insert or update a draft. Pass [existingId] to overwrite a previous draft. */
    fun saveDraft(context: Context, address: String, body: String, existingId: Int?): Long {
        val values = ContentValues().apply {
            put(Telephony.Sms.ADDRESS, address)
            put(Telephony.Sms.BODY, body)
            put(Telephony.Sms.DATE, System.currentTimeMillis())
            put(Telephony.Sms.READ, 1)
            put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_DRAFT)
        }
        return if (existingId != null) {
            val uri = Uri.withAppendedPath(Telephony.Sms.Draft.CONTENT_URI, existingId.toString())
            context.contentResolver.update(uri, values, null, null)
            existingId.toLong()
        } else {
            val uri = context.contentResolver.insert(Telephony.Sms.Draft.CONTENT_URI, values)
            uri?.lastPathSegment?.toLongOrNull() ?: -1L
        }
    }

    fun markRead(context: Context, ids: List<Long>, read: Boolean): Int {
        var updated = 0
        val values = ContentValues().apply { put(Telephony.Sms.READ, if (read) 1 else 0) }
        for (id in ids) {
            val uri = Uri.withAppendedPath(Telephony.Sms.CONTENT_URI, id.toString())
            updated += context.contentResolver.update(uri, values, null, null)
        }
        return updated
    }

    fun deleteMessages(context: Context, ids: List<Long>): Int {
        var deleted = 0
        for (id in ids) {
            val uri = Uri.withAppendedPath(Telephony.Sms.CONTENT_URI, id.toString())
            deleted += context.contentResolver.delete(uri, null, null)
        }
        return deleted
    }

    /**
     * Called by SmsDeliverReceiver when this app IS the default handler:
     * it is responsible for writing the incoming message into the provider
     * itself (the system does not do this automatically for the default app).
     */
    fun insertIncoming(context: Context, address: String?, body: String?, timestamp: Long): Long {
        val values = ContentValues().apply {
            put(Telephony.Sms.ADDRESS, address)
            put(Telephony.Sms.BODY, body)
            put(Telephony.Sms.DATE, timestamp)
            put(Telephony.Sms.DATE_SENT, timestamp)
            put(Telephony.Sms.READ, 0)
            put(Telephony.Sms.SEEN, 0)
            put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_INBOX)
        }
        val uri = context.contentResolver.insert(Telephony.Sms.Inbox.CONTENT_URI, values)
        return uri?.lastPathSegment?.toLongOrNull() ?: -1L
    }
}
