package com.smsorganizer.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Android requires a WAP_PUSH_DELIVER receiver for an app to be eligible as
 * the default SMS handler, but full MMS (multimedia) parsing is out of scope
 * for this MVP. We acknowledge receipt so the system doesn't retry, but do
 * not parse/store MMS content yet.
 *
 * TODO (future scope): parse the MMS PDU, extract text/image parts, and
 * insert into content://mms + content://mms/part so MMS threads show up
 * alongside SMS ones.
 */
class MmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Intentionally minimal — see TODO above.
    }
}
