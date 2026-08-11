package com.smsorganizer.app

import android.app.PendingIntent
import android.app.role.RoleManager
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.Telephony
import android.telephony.SmsManager
import androidx.core.app.NotificationManagerCompat

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

    // "sub_id" is the subscription id column backing dual-SIM messages —
    // present in the provider schema since API 22, but not exposed as a
    // Telephony.Sms constant on all SDK levels, so it's queried by its raw
    // column name. Queried as a separate, optional projection (see below)
    // since some ROMs / API<22 devices don't have it at all.
    private const val COLUMN_SUB_ID = "sub_id"

    private val baseProjection = arrayOf(
        Telephony.Sms._ID,
        Telephony.Sms.THREAD_ID,
        Telephony.Sms.ADDRESS,
        Telephony.Sms.BODY,
        Telephony.Sms.DATE,
        Telephony.Sms.DATE_SENT,
        Telephony.Sms.TYPE, // 1=inbox, 2=sent, 3=draft, 4=outbox, 5=failed, 6=queued
        Telephony.Sms.READ,
        Telephony.Sms.SEEN,
        Telephony.Sms.STATUS // -1=none, 0=complete/delivered, 32=pending, 64=failed
    )

    /**
     * Reads every row from content://sms (inbox + sent + draft + outbox).
     * Categorisation and thread-grouping happen on the Dart side; this just
     * returns raw rows as maps so we don't duplicate business logic natively.
     */
    fun getAllMessages(context: Context): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()

        // Try including sub_id first; fall back to the base projection if
        // the provider on this device/API level rejects the extra column
        // rather than crashing the whole sync over a dual-SIM nicety.
        var cursor = try {
            context.contentResolver.query(
                Telephony.Sms.CONTENT_URI, baseProjection + COLUMN_SUB_ID, null, null,
                "${Telephony.Sms.DATE} DESC"
            )
        } catch (_: Exception) {
            null
        }
        var hasSubId = cursor != null
        if (cursor == null) {
            cursor = context.contentResolver.query(
                Telephony.Sms.CONTENT_URI, baseProjection, null, null,
                "${Telephony.Sms.DATE} DESC"
            )
        }

        val subToSlot = SimRepository.subscriptionToSlotMap(context)

        cursor?.use {
            val subIdIdx = if (hasSubId) it.getColumnIndex(COLUMN_SUB_ID) else -1
            hasSubId = subIdIdx >= 0
            while (it.moveToNext()) {
                val subId = if (hasSubId) it.getInt(subIdIdx) else -1
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
                        "seen" to (it.getInt(it.getColumnIndexOrThrow(Telephony.Sms.SEEN)) == 1),
                        "status" to it.getInt(it.getColumnIndexOrThrow(Telephony.Sms.STATUS)),
                        // 0-based slot index (0="SIM 1", 1="SIM 2"), or -1 if
                        // unknown (permission not granted, single-SIM device,
                        // or the SIM that sent/received this has since been
                        // removed so it's no longer "active").
                        "simSlot" to (subToSlot[subId] ?: -1)
                    )
                )
            }
        }
        return results
    }

    /**
     * Sends an SMS and, since a default SMS app is responsible for its own
     * status in content://sms (the system does not insert or update it
     * automatically), writes the message ourselves — first as Outbox/
     * pending, then promotes it to Sent/Failed once SmsSendStatusReceiver
     * hears back from the radio for every part, and again to Delivered/
     * (delivery-)Failed if/when the carrier's delivery report arrives. See
     * SmsSendStatusReceiver.kt for the PendingIntent plumbing.
     *
     * [subscriptionId] picks which SIM sends it on a dual-SIM device — null
     * (or omitted) uses the device's default SmsManager, same as before this
     * parameter existed.
     *
     * Returns the inserted row's id (for [SmsSendStatusReceiver] to key its
     * tracking on), or -1 if the row couldn't be written — the send is still
     * attempted either way, it just won't have a status to update.
     */
    fun sendSms(context: Context, address: String, body: String, subscriptionId: Int? = null): Long {
        val smsManager = SimRepository.smsManagerFor(context, subscriptionId)
        val parts = smsManager.divideMessage(body)

        // Inserted via the base content://sms URI (not /sent, as before) —
        // unlike the Inbox/Sent/Draft convenience URIs, it doesn't force a
        // particular TYPE, so the row can start as Outbox/pending and only
        // become Sent once actually confirmed, while still getting the same
        // automatic thread_id assignment those convenience URIs give.
        val values = ContentValues().apply {
            put(Telephony.Sms.ADDRESS, address)
            put(Telephony.Sms.BODY, body)
            put(Telephony.Sms.DATE, System.currentTimeMillis())
            put(Telephony.Sms.READ, 1)
            put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_OUTBOX)
            put(Telephony.Sms.STATUS, Telephony.Sms.STATUS_PENDING)
            if (subscriptionId != null && subscriptionId >= 0) {
                put(COLUMN_SUB_ID, subscriptionId)
            }
        }
        val uri = context.contentResolver.insert(Telephony.Sms.CONTENT_URI, values)
        val rowId = uri?.lastPathSegment?.toLongOrNull() ?: -1L

        if (rowId == -1L) {
            // Couldn't record the row — still attempt the actual send so the
            // message goes out; it just won't show up as "Sending..."/get a
            // status in this app's own list, since there's no row to update.
            smsManager.sendMultipartTextMessage(address, null, parts, null, null)
            return rowId
        }

        try {
            SmsSendStatusReceiver.beginTracking(rowId, parts.size)
            val sentIntents = ArrayList<PendingIntent>(parts.size)
            val deliveryIntents = ArrayList<PendingIntent>(parts.size)
            for (i in parts.indices) {
                sentIntents.add(SmsSendStatusReceiver.sentPendingIntent(context, rowId, i))
                deliveryIntents.add(SmsSendStatusReceiver.deliveredPendingIntent(context, rowId, i))
            }
            smsManager.sendMultipartTextMessage(address, null, parts, sentIntents, deliveryIntents)
        } catch (e: Exception) {
            // The radio call itself failed synchronously (no SIM, permission
            // revoked mid-session, etc.) — the async sent-report callback
            // above will never fire in this case, so mark it failed here
            // instead of leaving the row stuck showing "Sending..." forever.
            markSentResult(context, rowId, success = false)
            throw e
        }
        return rowId
    }

    /** Called by SmsSendStatusReceiver once every part's "handed to radio" report is in. */
    fun markSentResult(context: Context, rowId: Long, success: Boolean) {
        val values = ContentValues().apply {
            put(
                Telephony.Sms.TYPE,
                if (success) Telephony.Sms.MESSAGE_TYPE_SENT else Telephony.Sms.MESSAGE_TYPE_FAILED
            )
            // A send failure has no later delivery report to wait for.
            if (!success) put(Telephony.Sms.STATUS, Telephony.Sms.STATUS_FAILED)
        }
        context.contentResolver.update(
            Uri.withAppendedPath(Telephony.Sms.CONTENT_URI, rowId.toString()), values, null, null
        )
    }

    /**
     * Called by SmsSendStatusReceiver once every part's delivery report is
     * in — only fires at all for carriers that actually send one; otherwise
     * the row simply stays at STATUS_PENDING (reads as "Sent", not
     * "Delivered") forever, which is the correct real-world behaviour.
     */
    fun markDeliveryResult(context: Context, rowId: Long, delivered: Boolean) {
        val values = ContentValues().apply {
            put(Telephony.Sms.STATUS, if (delivered) Telephony.Sms.STATUS_COMPLETE else Telephony.Sms.STATUS_FAILED)
        }
        context.contentResolver.update(
            Uri.withAppendedPath(Telephony.Sms.CONTENT_URI, rowId.toString()), values, null, null
        )
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

    /**
     * Marking read here (whether from the app's own UI or a notification
     * quick-action) is the one place all "read" state changes funnel
     * through, so it's also where the stacked notification for a thread
     * gets cleared once every incoming message in it has been read — the
     * notification group should only ever be stacking unread threads, not
     * ones the user has already caught up on.
     */
    fun markRead(context: Context, ids: List<Long>, read: Boolean): Int {
        var updated = 0
        val affectedThreadIds = mutableSetOf<Long>()
        val values = ContentValues().apply { put(Telephony.Sms.READ, if (read) 1 else 0) }
        for (id in ids) {
            val uri = Uri.withAppendedPath(Telephony.Sms.CONTENT_URI, id.toString())
            if (read) {
                context.contentResolver.query(
                    uri,
                    arrayOf(Telephony.Sms.THREAD_ID),
                    null,
                    null,
                    null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) affectedThreadIds.add(cursor.getLong(0))
                }
            }
            updated += context.contentResolver.update(uri, values, null, null)
        }
        if (read) {
            for (threadId in affectedThreadIds) {
                if (getUnreadIncomingIds(context, threadId).isEmpty()) {
                    NotificationManagerCompat.from(context).cancel(threadId.toInt())
                    ConversationHistoryStore.clear(context, threadId)
                }
            }
        }
        return updated
    }

    /**
     * Unread incoming message ids for [threadId] — backs the notification's
     * "Mark read" quick action, which (unlike the in-app markThreadRead)
     * has no already-loaded message list to filter and has to ask the
     * provider directly.
     */
    fun getUnreadIncomingIds(context: Context, threadId: Long): List<Long> {
        val ids = mutableListOf<Long>()
        val cursor = context.contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf(Telephony.Sms._ID),
            "${Telephony.Sms.THREAD_ID} = ? AND ${Telephony.Sms.READ} = 0 AND ${Telephony.Sms.TYPE} = ?",
            arrayOf(threadId.toString(), Telephony.Sms.MESSAGE_TYPE_INBOX.toString()),
            null
        )
        cursor?.use {
            val idIdx = it.getColumnIndexOrThrow(Telephony.Sms._ID)
            while (it.moveToNext()) {
                ids.add(it.getLong(idIdx))
            }
        }
        return ids
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
     *
     * [subscriptionId] is the SIM that received it, read off the SMS_DELIVER
     * intent's "subscription" extra by the receiver — -1/null if unavailable
     * (single-SIM device, or the extra wasn't present).
     */
    fun insertIncoming(
        context: Context,
        address: String?,
        body: String?,
        timestamp: Long,
        subscriptionId: Int? = null
    ): Long {
        val values = ContentValues().apply {
            put(Telephony.Sms.ADDRESS, address)
            put(Telephony.Sms.BODY, body)
            put(Telephony.Sms.DATE, timestamp)
            put(Telephony.Sms.DATE_SENT, timestamp)
            put(Telephony.Sms.READ, 0)
            put(Telephony.Sms.SEEN, 0)
            put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_INBOX)
            if (subscriptionId != null && subscriptionId >= 0) {
                put(COLUMN_SUB_ID, subscriptionId)
            }
        }
        val uri = context.contentResolver.insert(Telephony.Sms.Inbox.CONTENT_URI, values)
        return uri?.lastPathSegment?.toLongOrNull() ?: -1L
    }
}
