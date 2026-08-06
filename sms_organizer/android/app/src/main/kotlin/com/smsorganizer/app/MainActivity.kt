package com.smsorganizer.app

import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val METHOD_CHANNEL = "com.smsorganizer/sms"
        const val EVENT_CHANNEL = "com.smsorganizer/sms_events"
        const val REQUEST_DEFAULT_SMS_ROLE = 9001

        // Held statically so the broadcast receiver (which is not an Activity)
        // can push newly-arrived messages straight to Dart while the app is running.
        var eventSink: EventChannel.EventSink? = null
    }

    private var pendingRoleResult: MethodChannel.Result? = null

    // Kept as a field (not just a local val in configureFlutterEngine) so
    // onNewIntent can push a native-to-Dart call when a notification is
    // tapped while the app is already running.
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isDefaultSmsApp" -> result.success(SmsRepository.isDefaultSmsApp(this))
                "requestDefaultSmsApp" -> {
                    pendingRoleResult = result
                    requestDefaultSmsRole()
                }
                "getAllMessages" -> result.success(SmsRepository.getAllMessages(this))
                "getContacts" -> result.success(ContactsRepository.getAllContacts(this))
                "getActiveSims" -> result.success(SimRepository.getActiveSims(this))
                "getMutedCategories" ->
                    result.success(NotificationPrefsRepository.getMuted(this).toList())
                "setMutedCategories" -> {
                    val categories = (call.argument<List<String>>("categories") ?: emptyList()).toSet()
                    NotificationPrefsRepository.setMuted(this, categories)
                    result.success(null)
                }
                "getLaunchComposeExtras" -> {
                    val address = intent?.getStringExtra("compose_address")
                    val body = intent?.getStringExtra("compose_body")
                    if (address != null || body != null) {
                        result.success(mapOf("address" to address, "body" to body))
                        // Clear so re-reading (e.g. after a hot restart) doesn't re-trigger.
                        intent?.removeExtra("compose_address")
                        intent?.removeExtra("compose_body")
                    } else {
                        result.success(null)
                    }
                }
                "getLaunchNotificationThreadId" -> {
                    // Cold-start case: app was fully killed, then relaunched
                    // by tapping a notification. onNewIntent below handles
                    // the warm case (app already running) separately.
                    val threadId = intent?.getLongExtra("notification_thread_id", -1L) ?: -1L
                    if (threadId != -1L) {
                        intent?.removeExtra("notification_thread_id")
                        result.success(threadId)
                    } else {
                        result.success(null)
                    }
                }
                "sendSms" -> {
                    val address = call.argument<String>("address") ?: ""
                    val body = call.argument<String>("body") ?: ""
                    val subscriptionId = call.argument<Int>("subscriptionId")
                    try {
                        SmsRepository.sendSms(this, address, body, subscriptionId)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SEND_FAILED", e.message, null)
                    }
                }
                "saveDraft" -> {
                    val address = call.argument<String>("address") ?: ""
                    val body = call.argument<String>("body") ?: ""
                    val id = call.argument<Int>("id")
                    result.success(SmsRepository.saveDraft(this, address, body, id))
                }
                "markRead" -> {
                    val ids = call.argument<List<Long>>("ids") ?: emptyList()
                    val read = call.argument<Boolean>("read") ?: true
                    result.success(SmsRepository.markRead(this, ids, read))
                }
                "deleteMessages" -> {
                    val ids = call.argument<List<Long>>("ids") ?: emptyList()
                    result.success(SmsRepository.deleteMessages(this, ids))
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                }

                override fun onCancel(args: Any?) {
                    eventSink = null
                }
            })
    }

    /**
     * Warm case: the app is already running (backgrounded, not killed) and
     * the user taps a notification. Because MainActivity's launchMode is
     * singleTop, Android redelivers the intent here instead of creating a
     * new instance — but the Activity's `intent` property doesn't update
     * itself; setIntent(intent) is required so later reads (e.g. a
     * subsequent getLaunchNotificationThreadId call) see the new extras.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val threadId = intent.getLongExtra("notification_thread_id", -1L)
        if (threadId != -1L) {
            intent.removeExtra("notification_thread_id")
            methodChannel?.invokeMethod("onNotificationThreadTapped", threadId)
        }
    }

    private fun requestDefaultSmsRole() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(Context.ROLE_SERVICE) as RoleManager
            if (roleManager.isRoleAvailable(RoleManager.ROLE_SMS) &&
                !roleManager.isRoleHeld(RoleManager.ROLE_SMS)
            ) {
                val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_SMS)
                startActivityForResult(intent, REQUEST_DEFAULT_SMS_ROLE)
                return
            }
            pendingRoleResult?.success(SmsRepository.isDefaultSmsApp(this))
            pendingRoleResult = null
        } else {
            val intent = Intent(Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT)
            intent.putExtra(Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, packageName)
            startActivityForResult(intent, REQUEST_DEFAULT_SMS_ROLE)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_DEFAULT_SMS_ROLE) {
            pendingRoleResult?.success(SmsRepository.isDefaultSmsApp(this))
            pendingRoleResult = null
        }
    }
}
