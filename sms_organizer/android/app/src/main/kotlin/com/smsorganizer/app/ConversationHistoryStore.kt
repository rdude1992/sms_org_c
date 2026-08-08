package com.smsorganizer.app

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Small per-thread history of recent message text (mine and theirs), kept
 * purely so IncomingSmsNotifier can render a proper multi-line
 * MessagingStyle notification — and append a reply as it's sent — without
 * needing to read back Android's own rendered Notification object, which
 * is awkward to do reliably from a plain BroadcastReceiver. Capped short:
 * this only ever seeds what's visible in an active/recent notification,
 * never a source of truth (that's always content://sms).
 */
object ConversationHistoryStore {
    private const val PREFS_NAME = "sms_organizer_notification_history"
    private const val MAX_ENTRIES = 6

    data class Entry(val text: String, val timestamp: Long, val fromMe: Boolean)

    fun append(context: Context, threadId: Long, entry: Entry): List<Entry> {
        val prefs = prefs(context)
        val key = threadId.toString()
        val updated = (read(prefs, key) + entry).let {
            if (it.size > MAX_ENTRIES) it.takeLast(MAX_ENTRIES) else it
        }
        prefs.edit().putString(key, encode(updated)).apply()
        return updated
    }

    fun clear(context: Context, threadId: Long) {
        prefs(context).edit().remove(threadId.toString()).apply()
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun read(prefs: SharedPreferences, key: String): List<Entry> {
        val raw = prefs.getString(key, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map {
                val obj = array.getJSONObject(it)
                Entry(obj.getString("t"), obj.getLong("ts"), obj.getBoolean("m"))
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun encode(entries: List<Entry>): String {
        val array = JSONArray()
        for (entry in entries) {
            array.put(
                JSONObject().apply {
                    put("t", entry.text)
                    put("ts", entry.timestamp)
                    put("m", entry.fromMe)
                }
            )
        }
        return array.toString()
    }
}
