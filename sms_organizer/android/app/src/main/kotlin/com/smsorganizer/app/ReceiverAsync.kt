package com.smsorganizer.app

import android.content.BroadcastReceiver
import android.util.Log
import java.util.concurrent.Executors

/**
 * Background work for manifest receivers. onReceive runs on the main thread
 * with a ~10s budget, and provider writes + contact lookups + notification
 * building can exceed it, causing ANRs and jank. goAsync() keeps the broadcast
 * alive while the work runs on a single worker thread, which also keeps
 * incoming messages in arrival order.
 */
private val receiverExecutor = Executors.newSingleThreadExecutor()

fun BroadcastReceiver.runAsync(tag: String, work: () -> Unit) {
    val pending = goAsync()
    receiverExecutor.execute {
        try {
            work()
        } catch (e: Exception) {
            Log.e(tag, "Background receiver work failed", e)
        } finally {
            pending.finish()
        }
    }
}
