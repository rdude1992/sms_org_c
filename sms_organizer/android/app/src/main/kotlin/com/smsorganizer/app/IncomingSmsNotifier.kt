package com.smsorganizer.app

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.provider.Telephony
import android.text.Spannable
import android.text.SpannableString
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.app.RemoteInput
import androidx.core.content.ContextCompat
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import java.text.NumberFormat
import java.util.Locale

/**
 * Shared entry point called by both SmsDeliverReceiver (app is default) and
 * SmsReceivedReceiver (app is not yet default) to post a notification for
 * an incoming SMS, and by NotificationActionReceiver after a reply is sent
 * from the notification itself.
 *
 * This is the fix for the background-delivery gap: everything here runs in
 * plain Kotlin — categorisation, the mute check, contact-name lookup, and
 * the actual NotificationCompat call — with zero dependency on a running
 * Flutter engine or Dart VM. Android guarantees SmsDeliverReceiver fires
 * regardless of whether the app's process is alive, so as long as this
 * function doesn't itself need Dart, the notification is reliable even
 * when Android has fully killed the app.
 *
 * Notifications use MessagingStyle (a proper chat-style thread, with a
 * Person per sender) rather than a flat BigTextStyle, are tied to a
 * per-conversation shortcut/channel so Android recognises them as
 * "Conversations" (priority conversations, bubbles), and carry inline
 * reply / mark-read / copy-OTP actions so most interactions never need to
 * open the app at all.
 */
object IncomingSmsNotifier {

    private const val GROUP_KEY = "com.smsorganizer.app.INCOMING_SMS_GROUP"
    private const val SUMMARY_NOTIFICATION_ID = 0

    // Same brand tokens as lib/theme/app_colors.dart's AppColors.lightPrimary
    // (the app's one terracotta accent) and the credit/debit colors
    // TransactionTile uses everywhere in-app — kept in sync manually, same
    // caveat as OtpExtractor/Categorizer/TransactionExtractor.
    private val ACCENT_COLOR = Color.parseColor("#C96442")
    private val CREDIT_COLOR = Color.parseColor("#10B981")
    private val DEBIT_COLOR = Color.parseColor("#EF4444")

    private val indianAmountFormat: NumberFormat = NumberFormat.getIntegerInstance(Locale("en", "IN"))

    fun notify(context: Context, address: String?, body: String?) {
        if (address.isNullOrEmpty() || body.isNullOrEmpty()) return
        if (!hasNotificationPermission(context)) return

        val category = Categorizer.categorize(address, body)
        val muted = NotificationPrefsRepository.getMuted(context)
        if (muted.contains(category.prefKey)) return

        val threadId = Telephony.Threads.getOrCreateThreadId(context, address)
        val history = ConversationHistoryStore.append(
            context,
            threadId,
            ConversationHistoryStore.Entry(body, System.currentTimeMillis(), fromMe = false)
        )
        postNotification(context, threadId, address, body, category, history)
    }

    /**
     * Re-renders the thread's notification after a reply was just sent
     * from its inline-reply action, so the shade reflects the exchange
     * (the appended "you" message) instead of just disappearing.
     */
    fun notifyAfterReply(context: Context, threadId: Long, address: String, body: String) {
        if (!hasNotificationPermission(context)) return
        val category = Categorizer.categorize(address, body)
        val history = ConversationHistoryStore.append(
            context,
            threadId,
            ConversationHistoryStore.Entry(body, System.currentTimeMillis(), fromMe = true)
        )
        postNotification(context, threadId, address, body, category, history)
    }

    /**
     * Builds and posts the full rich notification, falling back to a bare
     * minimum one (guaranteed-to-exist parent channel, no actions, no
     * MessagingStyle/shortcut/bubble) if ANY part of that throws. This
     * matters because a notification posted against a channel id that
     * doesn't actually exist — which is exactly the failure mode a bug
     * anywhere upstream of the notify() call could cause — is silently
     * dropped by Android: no exception surfaces, no notification appears,
     * and there's nothing in the UI to explain why. Getting a plain
     * notification instead of a fancy one beats getting nothing.
     */
    private fun postNotification(
        context: Context,
        threadId: Long,
        address: String,
        body: String,
        category: Categorizer.Category,
        history: List<ConversationHistoryStore.Entry>
    ) {
        try {
            postRichNotification(context, threadId, address, category, history)
        } catch (e: Exception) {
            // Logged at ERROR (not silently swallowed) specifically so this
            // is greppable in logcat — `adb logcat | grep IncomingSmsNotif`
            // around an incoming SMS shows exactly what's throwing here,
            // rather than just "it fell back to the plain notification".
            Log.e("IncomingSmsNotif", "Rich notification failed, falling back to plain", e)
            postFallbackNotification(context, threadId, address, body, category)
        }
    }

    private fun postRichNotification(
        context: Context,
        threadId: Long,
        address: String,
        category: Categorizer.Category,
        history: List<ConversationHistoryStore.Entry>
    ) {
        NotificationChannels.ensureCreated(context)
        val displayName = ContactsRepository.lookupDisplayName(context, address) ?: address
        val channelId =
            NotificationChannels.ensureConversationChannel(context, category.prefKey, threadId, displayName)

        val contactIcon = ContactsRepository.lookupPhotoIcon(context, address)
        val fallbackIcon = IconCompat.createWithResource(context, R.mipmap.ic_launcher)
        val avatarIcon = contactIcon ?: fallbackIcon

        val sender = Person.Builder().setName(displayName).setIcon(avatarIcon).build()
        val me = Person.Builder().setName("You").build()

        val style = NotificationCompat.MessagingStyle(me).setConversationTitle(displayName)
        for (entry in history) {
            // Only ever applied to incoming text — an outgoing "You" reply is
            // never an OTP or a bank alert. Tried regardless of this
            // notification's own [category]: a thread can carry more than
            // one category over time (a bank sender mixing promo and
            // transactional SMS), and each extractor already returns the
            // plain text unchanged when it finds nothing to highlight, so
            // there's no need to track a per-message category to gate this.
            val text = if (entry.fromMe) entry.text else formatIncomingMessage(entry.text)
            style.addMessage(text, entry.timestamp, if (entry.fromMe) null else sender)
        }

        val shortcutId = "conv_$threadId"
        publishShortcut(context, shortcutId, displayName, sender, avatarIcon)

        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("notification_thread_id", threadId)
        }
        val contentIntent = PendingIntent.getActivity(
            context,
            threadId.toInt(),
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        // Bubbles specifically require a MUTABLE PendingIntent — the
        // opposite of the (correctly immutable) one above — so this can't
        // just reuse contentIntent. Posting a BubbleMetadata built from an
        // immutable intent doesn't fail until the system server validates
        // it at notify() time, as an IllegalArgumentException ("PendingIntents
        // attached to bubbles must be mutable") that's easy to mistake for
        // something else going wrong in the rich notification path.
        val bubbleIntent = PendingIntent.getActivity(
            context,
            threadId.toInt() * 10 + 4,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setStyle(style)
            .setShortcutId(shortcutId)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(
                if (category == Categorizer.Category.OTP) NotificationCompat.PRIORITY_HIGH
                else NotificationCompat.PRIORITY_DEFAULT
            )
            .setGroup(GROUP_KEY)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .addAction(buildReplyAction(context, threadId, address))
            .addAction(buildMarkReadAction(context, threadId))

        if (category == Categorizer.Category.OTP) {
            val lastIncoming = history.lastOrNull { !it.fromMe }?.text
            val otpCode = lastIncoming?.let(OtpExtractor::extract)
            if (otpCode != null) {
                builder.addAction(buildCopyOtpAction(context, threadId, otpCode))
            }
        }

        attachBubbleMetadata(builder, bubbleIntent, avatarIcon)

        try {
            NotificationManagerCompat.from(context).notify(threadId.toInt(), builder.build())
            postGroupSummary(context)
        } catch (e: SecurityException) {
            // Permission was revoked between the check above and this call
            // (e.g. user turned it off in Settings mid-broadcast) — the
            // message is still safely in content://sms either way.
            Log.w("IncomingSmsNotif", "Notify denied by SecurityException", e)
        }
    }

    /**
     * The plain, minimal notification this replaced (BigTextStyle, the
     * always-present parent category channel, a content intent, nothing
     * fancier) — the safety net [postNotification] falls back to if
     * anything in [postRichNotification] throws.
     */
    private fun postFallbackNotification(
        context: Context,
        threadId: Long,
        address: String,
        body: String,
        category: Categorizer.Category
    ) {
        try {
            NotificationChannels.ensureCreated(context)
            val displayName = ContactsRepository.lookupDisplayName(context, address) ?: address

            val openIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("notification_thread_id", threadId)
            }
            val contentIntent = PendingIntent.getActivity(
                context,
                threadId.toInt(),
                openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notification = NotificationCompat.Builder(context, "sms_${category.prefKey}")
                .setSmallIcon(R.drawable.ic_stat_notify)
                .setContentTitle(displayName)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(
                    if (category == Categorizer.Category.OTP) NotificationCompat.PRIORITY_HIGH
                    else NotificationCompat.PRIORITY_DEFAULT
                )
                .setAutoCancel(true)
                .setContentIntent(contentIntent)
                .build()

            NotificationManagerCompat.from(context).notify(threadId.toInt(), notification)
        } catch (e: Exception) {
            // At this point we've already tried the rich path and this
            // minimal one — nothing left to reasonably fall back to, but
            // this is the one that would explain total silence, so log it.
            Log.e("IncomingSmsNotif", "Fallback notification also failed", e)
        }
    }

    /**
     * Best-effort highlighting for one incoming message's notification text
     * — bigger/bolder OTP codes, or a compact colored amount + payee/account
     * summary for transactional SMS (see the Truecaller-style reference this
     * was modeled after, adapted to the app's own accent/credit/debit
     * colors). Falls through to the plain [text] whenever neither extractor
     * finds anything, or if formatting itself throws — this only ever
     * decorates a notification, never blocks one.
     */
    private fun formatIncomingMessage(text: String): CharSequence {
        return try {
            formatOtpMessage(text) ?: formatTransactionMessage(text) ?: text
        } catch (e: Exception) {
            Log.w("IncomingSmsNotif", "Message formatting failed (non-fatal)", e)
            text
        }
    }

    /** Enlarges, bolds, and accent-colors the OTP code within [body], if any. */
    private fun formatOtpMessage(body: String): CharSequence? {
        val code = OtpExtractor.extract(body) ?: return null
        val index = body.indexOf(code)
        if (index < 0) return null
        val spannable = SpannableString(body)
        val end = index + code.length
        spannable.setSpan(RelativeSizeSpan(1.5f), index, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        spannable.setSpan(StyleSpan(Typeface.BOLD), index, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        spannable.setSpan(ForegroundColorSpan(ACCENT_COLOR), index, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        return spannable
    }

    /**
     * Prepends a Truecaller-style "+/-₹amount" line (credit-green or
     * debit-red, bold and enlarged) followed by a plain "Paid to X from
     * Account YYYY" / "Received from X into Account YYYY" summary, built
     * from whatever [TransactionExtractor] managed to find. Returns null —
     * leaving the original SMS text untouched — whenever there's no amount,
     * or the direction is ambiguous/a reversal, since a wrong "+"/"-" would
     * be actively misleading.
     */
    private fun formatTransactionMessage(body: String): CharSequence? {
        val details = TransactionExtractor.extract(body)
        val amount = details.amount ?: return null
        if (details.direction == TransactionExtractor.Direction.UNKNOWN ||
            details.direction == TransactionExtractor.Direction.REVERSAL
        ) {
            return null
        }
        val isCredit = details.direction == TransactionExtractor.Direction.CREDIT
        val sign = if (isCredit) "+" else "-"
        val color = if (isCredit) CREDIT_COLOR else DEBIT_COLOR
        val amountText = "$sign₹${formatAmount(amount)}"

        val descriptionParts = mutableListOf<String>()
        details.merchant?.let { descriptionParts.add(if (isCredit) "from $it" else "to $it") }
        details.account?.let {
            val preposition = if (isCredit) "into" else "from"
            descriptionParts.add("$preposition Account ${it.removePrefix("XX")}")
        }
        val verb = if (isCredit) "Received" else "Paid"
        val description = if (descriptionParts.isEmpty()) "" else "$verb ${descriptionParts.joinToString(" ")}"

        val full = if (description.isEmpty()) amountText else "$amountText\n$description"
        val spannable = SpannableString(full)
        spannable.setSpan(RelativeSizeSpan(1.25f), 0, amountText.length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        spannable.setSpan(StyleSpan(Typeface.BOLD), 0, amountText.length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        spannable.setSpan(ForegroundColorSpan(color), 0, amountText.length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        return spannable
    }

    /** Indian-locale (lakh/crore) digit grouping, matching Formatters.currency() in Dart. */
    private fun formatAmount(amount: Double): String = indianAmountFormat.format(Math.round(amount))

    private fun buildReplyAction(context: Context, threadId: Long, address: String): NotificationCompat.Action {
        val remoteInput = RemoteInput.Builder(NotificationActionReceiver.KEY_REPLY_TEXT)
            .setLabel("Reply")
            .build()
        val replyIntent = Intent(context, NotificationActionReceiver::class.java).apply {
            action = NotificationActionReceiver.ACTION_REPLY
            putExtra(NotificationActionReceiver.EXTRA_THREAD_ID, threadId)
            putExtra(NotificationActionReceiver.EXTRA_ADDRESS, address)
        }
        // RemoteInput actions must carry a mutable PendingIntent — Android
        // rejects the reply otherwise on API 31+.
        val replyPendingIntent = PendingIntent.getBroadcast(
            context,
            threadId.toInt() * 10 + 1,
            replyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )
        return NotificationCompat.Action.Builder(
            IconCompat.createWithResource(context, android.R.drawable.ic_menu_send),
            "Reply",
            replyPendingIntent
        ).addRemoteInput(remoteInput).setAllowGeneratedReplies(true).build()
    }

    private fun buildMarkReadAction(context: Context, threadId: Long): NotificationCompat.Action {
        val intent = Intent(context, NotificationActionReceiver::class.java).apply {
            action = NotificationActionReceiver.ACTION_MARK_READ
            putExtra(NotificationActionReceiver.EXTRA_THREAD_ID, threadId)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            threadId.toInt() * 10 + 2,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Action.Builder(
            IconCompat.createWithResource(context, android.R.drawable.ic_menu_view),
            "Mark read",
            pendingIntent
        ).build()
    }

    private fun buildCopyOtpAction(context: Context, threadId: Long, code: String): NotificationCompat.Action {
        val intent = Intent(context, NotificationActionReceiver::class.java).apply {
            action = NotificationActionReceiver.ACTION_COPY_OTP
            putExtra(NotificationActionReceiver.EXTRA_THREAD_ID, threadId)
            putExtra(NotificationActionReceiver.EXTRA_OTP_CODE, code)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            threadId.toInt() * 10 + 3,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Action.Builder(
            IconCompat.createWithResource(context, android.R.drawable.ic_menu_save),
            "Copy $code",
            pendingIntent
        ).build()
    }

    /**
     * A long-lived dynamic shortcut is, alongside setShortcutId() on the
     * notification, what lets Android recognise this thread as a
     * "Conversation" — surfaced in its own shade section and eligible for
     * bubbles. Best-effort: the per-launcher shortcut cap or a launcher
     * that doesn't support shortcuts at all just means the notification
     * falls back to being a normal one, not a crash.
     */
    private fun publishShortcut(
        context: Context,
        shortcutId: String,
        displayName: String,
        person: Person,
        icon: IconCompat
    ) {
        try {
            val shortcut = ShortcutInfoCompat.Builder(context, shortcutId)
                .setLongLived(true)
                .setShortLabel(displayName)
                .setIcon(icon)
                .setPerson(person)
                .setIntent(Intent(context, MainActivity::class.java).setAction(Intent.ACTION_VIEW))
                .build()
            ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)
        } catch (e: Exception) {
            Log.w("IncomingSmsNotif", "Shortcut publish failed (non-fatal)", e)
        }
    }

    /**
     * Best-effort: bubbles require API 30+ and are opt-in per conversation
     * by the user regardless. [bubbleIntent] must be a MUTABLE
     * PendingIntent — Android rejects the whole notification at post time
     * otherwise (see the comment where it's built in [postRichNotification]).
     */
    private fun attachBubbleMetadata(
        builder: NotificationCompat.Builder,
        bubbleIntent: PendingIntent,
        icon: IconCompat
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        try {
            val metadata = NotificationCompat.BubbleMetadata.Builder(bubbleIntent, icon)
                .setDesiredHeight(600)
                .setAutoExpandBubble(false)
                .setSuppressNotification(false)
                .build()
            builder.setBubbleMetadata(metadata)
        } catch (e: Exception) {
            Log.w("IncomingSmsNotif", "Bubble metadata failed (non-fatal)", e)
        }
    }

    /**
     * Bundles multiple per-thread notifications under one summary so
     * several new conversations arriving close together collapse into
     * "N new messages" instead of stacking up separate heads-up banners.
     * Safe to re-post on every single notification — Android only shows
     * the summary once there's more than one notification in [GROUP_KEY].
     */
    private fun postGroupSummary(context: Context) {
        try {
            val summary = NotificationCompat.Builder(context, NotificationChannels.SUMMARY_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_notify)
                .setStyle(NotificationCompat.InboxStyle().setSummaryText("New messages"))
                .setGroup(GROUP_KEY)
                .setGroupSummary(true)
                .setAutoCancel(true)
                .build()
            NotificationManagerCompat.from(context).notify(SUMMARY_NOTIFICATION_ID, summary)
        } catch (_: SecurityException) {
        }
    }

    private fun hasNotificationPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    }
}
