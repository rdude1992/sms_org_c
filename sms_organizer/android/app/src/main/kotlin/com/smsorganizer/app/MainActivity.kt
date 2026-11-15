package com.smsorganizer.app

import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.provider.Telephony
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not plain FlutterActivity) is required by the
// local_auth plugin's Android implementation — it shows the system
// biometric prompt via androidx.biometric.BiometricPrompt, which needs a
// FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {

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

        // Ensures channels exist as soon as the app is opened (not just
        // lazily on the first incoming SMS), so Settings can query their
        // real system-level importance right away.
        NotificationChannels.ensureCreated(this)

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
                "openContact" -> {
                    val number = call.argument<String>("number") ?: ""
                    result.success(openContact(number))
                }
                "getActiveSims" -> result.success(SimRepository.getActiveSims(this))
                "getMutedCategories" ->
                    result.success(NotificationPrefsRepository.getMuted(this).toList())
                "setMutedCategories" -> {
                    val categories = (call.argument<List<String>>("categories") ?: emptyList()).toSet()
                    NotificationPrefsRepository.setMuted(this, categories)
                    // Reflects the new mute state onto the actual OS channel
                    // importance too, so the "tune" button's system settings
                    // page shows "Off" for a muted category instead of its
                    // normal "Alert" importance — see
                    // NotificationChannels.syncMuteState.
                    NotificationChannels.syncMuteState(this)
                    result.success(null)
                }
                "getChannelImportance" -> {
                    val channelId = call.argument<String>("channelId") ?: ""
                    result.success(NotificationChannels.channelImportance(this, channelId))
                }
                "openChannelSettings" -> {
                    val channelId = call.argument<String>("channelId") ?: ""
                    openChannelSettings(channelId)
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
                "restoreMessagesToDevice" -> {
                    if (!SmsRepository.isDefaultSmsApp(this)) {
                        result.error("NOT_DEFAULT_SMS_APP", "App must be the default SMS app to restore.", null)
                    } else {
                        val messages = call.argument<List<Map<String, Any?>>>("messages") ?: emptyList()
                        result.success(SmsRepository.restoreMessages(this, messages))
                    }
                }
                "clearAllDeviceMessages" -> {
                    if (!SmsRepository.isDefaultSmsApp(this)) {
                        result.error("NOT_DEFAULT_SMS_APP", "App must be the default SMS app to clear messages.", null)
                    } else {
                        result.success(SmsRepository.deleteAllMessages(this))
                    }
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

    /**
     * Deep-links straight into the OS's per-channel notification settings
     * (sound, vibration, badge, "priority conversation") for [channelId],
     * so those controls — which this app has no UI of its own for — are
     * one tap away instead of requiring the user to hunt through Settings
     * manually. Falls back to the app-level notification settings screen
     * pre-O, where individual channels don't exist as a concept yet.
     */
    private fun openChannelSettings(channelId: String) {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
            }
        } else {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra("app_package", packageName)
                putExtra("app_uid", applicationInfo.uid)
            }
        }
        try {
            startActivity(intent)
        } catch (_: Exception) {
            // No Settings app able to resolve this intent — nothing
            // sensible to do beyond not crashing.
        }
    }

    /**
     * Opens the system Contacts app's detail page for whichever saved
     * contact [number] matches — ThreadScreen's tap-to-open-contact action
     * on the phone number line under the conversation title. Returns false
     * (rather than throwing) for "no match"/"no Contacts app to handle it"
     * alike, since Dart only needs to know whether to show a fallback
     * message, not why it failed.
     */
    private fun openContact(number: String): Boolean {
        val uri = ContactsRepository.getLookupUri(this, number) ?: return false
        return try {
            startActivity(Intent(Intent.ACTION_VIEW, uri))
            true
        } catch (_: Exception) {
            false
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
