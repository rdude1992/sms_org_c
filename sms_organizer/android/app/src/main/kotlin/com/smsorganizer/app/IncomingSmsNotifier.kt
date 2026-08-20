package com.smsorganizer.app

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import android.provider.Telephony
import android.text.Spannable
import android.text.SpannableString
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.util.Log
import android.widget.RemoteViews
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

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_stat_notify)
            // Explicit rather than left for the OS/launcher to derive from
            // somewhere else (some render an inconsistent badge tint
            // otherwise) — same accent used for the in-notification amount/
            // OTP highlighting below, so the badge and the highlighted text
            // read as the one brand color.
            .setColor(ACCENT_COLOR)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setGroup(GROUP_KEY)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)

        // OTP gets its own plain, purpose-built layout (title + boxed-digit
        // code + Copy/Delete only) rather than the chat-style Conversation
        // treatment every other category gets — a one-shot code isn't a
        // conversation you reply to or mark read.
        if (category == Categorizer.Category.OTP) {
            configureOtpNotification(context, builder, threadId, displayName, history)
        } else {
            configureConversationNotification(context, builder, threadId, address, displayName, history, openIntent)
        }

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
     * The chat-style MessagingStyle "Conversation" treatment — a Person per
     * sender, shortcut + bubble eligibility, reply/mark-read/delete actions
     * — used for every category except OTP (see [configureOtpNotification]).
     */
    private fun configureConversationNotification(
        context: Context,
        builder: NotificationCompat.Builder,
        threadId: Long,
        address: String,
        displayName: String,
        history: List<ConversationHistoryStore.Entry>,
        openIntent: Intent
    ) {
        val contactIcon = ContactsRepository.lookupPhotoIcon(context, address)
        val avatarIcon = contactIcon ?: buildDefaultAvatarIcon(displayName)

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

        // Bubbles specifically require a MUTABLE PendingIntent — the
        // opposite of the (correctly immutable) contentIntent already set on
        // [builder] — so this needs its own. Posting a BubbleMetadata built
        // from an immutable intent doesn't fail until the system server
        // validates it at notify() time, as an IllegalArgumentException
        // ("PendingIntents attached to bubbles must be mutable") that's easy
        // to mistake for something else going wrong in the rich notification
        // path.
        val bubbleIntent = PendingIntent.getActivity(
            context,
            threadId.toInt() * 10 + 4,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )

        builder
            .setStyle(style)
            .setShortcutId(shortcutId)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .addAction(buildReplyAction(context, threadId, address))
            .addAction(buildMarkReadAction(context, threadId))
            .addAction(buildDeleteAction(context, threadId))

        attachBubbleMetadata(builder, bubbleIntent, avatarIcon)
    }

    /**
     * OTP layout: content title is the sender. The collapsed/heads-up peek
     * shows just [buildOtpDigitsView]'s bubble (System UI gives that state a
     * much tighter height budget, no room for the full message too); the
     * expanded body shows the same bubble via [buildOtpExpandedView] plus
     * the full raw SMS text below it, so pulling the notification down
     * gives the complete message rather than just the isolated code. Only
     * Copy and Delete actions — see [configureConversationNotification] for
     * why Reply/Mark read are skipped here.
     *
     * Deliberately does NOT put the raw code into contentText the way
     * [formatOtpMessage] would — Android's own notification handling scans a
     * notification's plain text content for OTP-shaped strings and, when it
     * finds one, adds its own "Copy" suggestion chip independent of
     * anything the app does. Since the code is already both visible (in the
     * bubble bitmap, which isn't plain text the OS can scan) and copyable
     * (our own explicit action below), leaving a second copy of the code in
     * contentText only bought a second, redundant system-generated copy
     * affordance for no benefit.
     */
    private fun configureOtpNotification(
        context: Context,
        builder: NotificationCompat.Builder,
        threadId: Long,
        displayName: String,
        history: List<ConversationHistoryStore.Entry>
    ) {
        builder.setContentTitle(displayName).setPriority(NotificationCompat.PRIORITY_HIGH)

        val lastIncoming = history.lastOrNull { !it.fromMe }?.text
        if (lastIncoming != null) {
            val otpCode = OtpExtractor.extract(lastIncoming)
            if (otpCode != null) {
                builder
                    .setContentText("One-time code")
                    .setStyle(NotificationCompat.DecoratedCustomViewStyle())
                    .setCustomContentView(buildOtpDigitsView(context, otpCode, compact = true))
                    .setCustomBigContentView(buildOtpExpandedView(context, otpCode, lastIncoming))
                    .addAction(buildCopyOtpAction(context, threadId, otpCode))
            } else {
                // No code found by OtpExtractor (rare — the two extractors
                // aren't identical) — there's no bubble to fall back on, so
                // the raw text is the only way to show anything at all;
                // showing it plainly (and accepting whatever the OS does
                // with it) beats an empty-looking notification.
                builder
                    .setContentText(formatOtpMessage(lastIncoming) ?: lastIncoming)
                    .setStyle(NotificationCompat.BigTextStyle().bigText(lastIncoming))
            }
        }

        builder.addAction(buildDeleteAction(context, threadId))
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
                .setColor(ACCENT_COLOR)
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

    /**
     * Generic sender avatar for when [ContactsRepository.lookupPhotoIcon]
     * has nothing to show — no matching contact (a bank/OTP shortcode like
     * "HDFCBK", say) or no permission. Previously fell back to the app's
     * own launcher icon, which — cropped into the notification shade's
     * circular avatar slot — reads as "the app icon has a weird background"
     * rather than as a per-sender placeholder. Drawn as an accent-colored
     * circle with [displayName]'s first letter, matching how most
     * messaging/contacts apps placeholder a contact with no photo; a sender
     * whose name has no letter in it at all (a bare phone number) gets a
     * plain person silhouette instead of a stray digit.
     */
    private fun buildDefaultAvatarIcon(displayName: String): IconCompat {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ACCENT_COLOR
        })

        val initial = displayName.trim().firstOrNull { it.isLetter() }?.uppercaseChar()
        if (initial != null) {
            val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                textSize = size * 0.46f
                textAlign = Paint.Align.CENTER
                typeface = Typeface.DEFAULT_BOLD
            }
            val textY = size / 2f - (textPaint.descent() + textPaint.ascent()) / 2f
            canvas.drawText(initial.toString(), size / 2f, textY, textPaint)
        } else {
            val personPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
            canvas.drawCircle(size / 2f, size * 0.38f, size * 0.16f, personPaint)
            val shoulders = RectF(size * 0.26f, size * 0.56f, size * 0.74f, size * 0.92f)
            canvas.drawArc(shoulders, 180f, 180f, true, personPaint)
        }
        return IconCompat.createWithBitmap(bitmap)
    }

    /**
     * Wraps [buildOtpBubbleBitmap] in the RemoteViews layout that hosts it —
     * see notification_otp_digits.xml. [compact], when true, renders a
     * smaller version of the same bubble for the collapsed/heads-up custom
     * content view, which System UI gives a much tighter height budget than
     * the fully expanded big content view.
     */
    private fun buildOtpDigitsView(context: Context, code: String, compact: Boolean): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.notification_otp_digits)
        views.setImageViewBitmap(R.id.otp_digits_image, buildOtpBubbleBitmap(context, code, compact))
        return views
    }

    /**
     * The expanded (pulled-down) body: the full-size bubble on top, plus the
     * complete raw SMS [message] below it — see notification_otp_digits_expanded.xml
     * — so expanding shows the whole message, not just the isolated code.
     */
    private fun buildOtpExpandedView(context: Context, code: String, message: String): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.notification_otp_digits_expanded)
        views.setImageViewBitmap(R.id.otp_digits_image, buildOtpBubbleBitmap(context, code, compact = false))
        views.setTextViewText(R.id.otp_message_text, message)
        return views
    }

    /**
     * Renders [code] as a single solid black "sent message" bubble with
     * white text — the same "draw it ourselves with a Canvas" approach
     * [buildDefaultAvatarIcon] already uses, needed here for the same
     * underlying reason: RemoteViews content draws inside the
     * hardware-accelerated System UI process, so building the bubble as a
     * bitmap keeps full control over its look regardless of what any given
     * OEM's notification host does with an inflated `<shape>`. Sized for the
     * common 4-6 digit case; an 8-char code (OtpExtractor's upper bound)
     * renders wider and may get clipped by the notification's own width
     * rather than wrapping — an accepted degradation rather than shrinking
     * every more-common shorter code to accommodate the rare long one.
     * [compact]'s box/font sizes are close to (not much smaller than) the
     * full size — the collapsed/heads-up row is still readable at a glance,
     * just slightly tighter to respect that state's smaller height budget.
     */
    private fun buildOtpBubbleBitmap(context: Context, code: String, compact: Boolean): Bitmap {
        val density = context.resources.displayMetrics.density
        fun dp(v: Float) = v * density

        val textSizePx = dp(if (compact) 19f else 20f)
        val horizontalPadding = dp(if (compact) 17f else 18f)
        val verticalPadding = dp(10f)
        val corner = dp(if (compact) 17f else 18f)

        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = textSizePx
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
            letterSpacing = if (compact) 0.15f else 0.16f
        }

        val textWidth = textPaint.measureText(code)
        val fontMetrics = textPaint.fontMetrics
        val textHeight = fontMetrics.descent - fontMetrics.ascent

        val width = (textWidth + horizontalPadding * 2).toInt().coerceAtLeast(1)
        val height = (textHeight + verticalPadding * 2).toInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val bubblePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = Color.BLACK
        }
        canvas.drawRoundRect(RectF(0f, 0f, width.toFloat(), height.toFloat()), corner, corner, bubblePaint)

        val textY = height / 2f - (fontMetrics.descent + fontMetrics.ascent) / 2f
        canvas.drawText(code, width / 2f, textY, textPaint)
        return bitmap
    }

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

    private fun buildDeleteAction(context: Context, threadId: Long): NotificationCompat.Action {
        val intent = Intent(context, NotificationActionReceiver::class.java).apply {
            action = NotificationActionReceiver.ACTION_DELETE
            putExtra(NotificationActionReceiver.EXTRA_THREAD_ID, threadId)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            threadId.toInt() * 10 + 5,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Action.Builder(
            IconCompat.createWithResource(context, android.R.drawable.ic_menu_delete),
            "Delete",
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
                .setColor(ACCENT_COLOR)
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
