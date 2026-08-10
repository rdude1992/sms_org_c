package com.smsorganizer.app

/**
 * Native mirror of lib/services/categorization_service.dart, which is
 * itself a port of categorizeMessage(sender, content) from the project's
 * source smsParser.ts. Used only to decide which notification channel to
 * post on and whether that category is muted, for the case where no
 * Flutter engine is running to do the real classification that drives the
 * in-app UI.
 *
 * Keep this in sync manually if the Dart side changes — there's no code
 * sharing between Kotlin and Dart here, so the two can drift if only one
 * gets updated.
 */
object Categorizer {
    enum class Category(val prefKey: String) {
        PERSONAL("personal"),
        PROMOTIONAL("promotional"),
        TRANSACTIONAL("transactional"),
        OTP("otp"),
        UPDATES("updates"),
    }

    private val amountRegex = Regex("(?:rs\\.?|inr|₹)\\s*[\\d,]+(?:\\.\\d{1,2})?", RegexOption.IGNORE_CASE)
    private val suffixRegex = Regex("-([PSTG])$", RegexOption.IGNORE_CASE)
    private val otpIsYourOtpRegex = Regex("is your otp", RegexOption.IGNORE_CASE)
    private val digitCodeRegex = Regex("\\b\\d{4,8}\\b")
    private val willBeDebitedCreditedRegex = Regex("will\\s+be\\s+(?:debited|credited)", RegexOption.IGNORE_CASE)
    private val scheduledRegex = Regex("scheduled", RegexOption.IGNORE_CASE)
    private val initiatedRegex = Regex("initiated", RegexOption.IGNORE_CASE)
    private val cardEndingRegex = Regex("card.*(?:ending|xxxx|xx\\d{4})", RegexOption.IGNORE_CASE)
    // 'nfo' (New Fund Offer) as a bare substring also matches inside the
    // ordinary word "info"/"Info:" — a field label many routine bank
    // debit/credit alerts use (e.g. "Info: ACH D-..."). Word-bounded so it
    // only matches the standalone "NFO" abbreviation — mirrors the fix in
    // lib/services/categorization_service.dart's isPromotion check.
    private val nfoWordRegex = Regex("\\bnfo\\b", RegexOption.IGNORE_CASE)

    private val otpKeywords = listOf(
        "otp", "verification code", "verify", "code is", "passcode", "pin is",
        "one time password", "auth code"
    )

    private val promoKeywords = listOf(
        "offer", "sale", "discount", "% off", "flat off", "deal", "free", "win", "prize",
        "cashback", "coupon", "limited time", "hurry", "shop now", "buy now", "grab",
        "exclusive", "rewards", "points", "congrats", "play now",
        "recharge", "data", "validity", "use code",
        "create wealth", "achieve your life goals", "start a sip", "opportunity",
        "nfo", "new fund offer", "is live", "opens today", "closes on", "subscribe now",
        "markets have fallen", "time to top up", "click here to invest"
    )

    private val transactionKeywords = listOf(
        "credited", "debited", "spent", "paid", "received", "transfer",
        "balance", "a/c", "account", "transaction", "payment", "upi", "bank",
        "withdrawn", "purchase", "card", "limit", "pluxee", "sodexo",
        "sip", "folio", "nav", "units", "equity", "redemption", "allotted"
    )

    private val bankSenders = listOf(
        "bank", "hdfc", "icici", "sbi", "axis", "kotak", "paytm", "phonepe",
        "gpay", "upi", "abcamc", "miraei", "mutual", "fund", "broking"
    )

    private val updateKeywords = listOf(
        "delivered", "out for delivery", "dispatched", "shipped", "arriving", "courier", "package", "order",
        "pnr", "booking confirmed", "ticket", "flight", "train", "bus", "cab", "driver", "ride",
        "bill generated", "invoice", "due date", "statement", "plan expire"
    )

    fun categorize(sender: String, content: String): Category {
        val contentLower = content.lowercase()
        val senderLower = sender.lowercase()
        val senderUpper = sender.uppercase()

        // 0. Updates/Notifications (highest priority).
        if (contentLower.contains("view statement") ||
            contentLower.contains("account statement") ||
            contentLower.contains("a/c statement") ||
            contentLower.contains("download statement") ||
            contentLower.contains("statement of account") ||
            contentLower.contains("statement for folio") ||
            (contentLower.contains("stmt") &&
                (contentLower.contains("view") || contentLower.contains("click") || contentLower.contains("check"))) ||
            (contentLower.contains("redemption transaction") && contentLower.contains("processed")) ||
            (contentLower.contains("due") &&
                (contentLower.contains("debit") || contentLower.contains("payment") || contentLower.contains("sip"))) ||
            contentLower.contains("nomination") ||
            contentLower.contains("nominee") ||
            contentLower.contains("thank you for choosing")
        ) {
            return Category.UPDATES
        }

        if ((contentLower.contains("investment value") || contentLower.contains("total holding") || contentLower.contains("current value")) &&
            (contentLower.contains("as on") || contentLower.contains("is rs"))
        ) {
            return Category.UPDATES
        }

        if ((contentLower.contains("available balance") ||
                contentLower.contains("account balance") ||
                contentLower.contains("clear balance") ||
                contentLower.contains("total balance")) &&
            !contentLower.contains("spent") &&
            !contentLower.contains("paid") &&
            !contentLower.contains("debited") &&
            !contentLower.contains("withdrawn") &&
            !contentLower.contains("sent to") &&
            !contentLower.contains("transferred to")
        ) {
            return Category.UPDATES
        }

        val suffixMatch = suffixRegex.find(sender)
        val suffixCategory: Category? = suffixMatch?.groupValues?.get(1)?.uppercase()?.let { suffix ->
            when (suffix) {
                "P" -> Category.PROMOTIONAL
                "S", "G" -> Category.UPDATES
                "T" -> Category.TRANSACTIONAL
                else -> null
            }
        }

        // 1. OTP detection.
        val hasOtpKeyword = otpKeywords.any { contentLower.contains(it) }
        val hasDigitCode = digitCodeRegex.containsMatchIn(content)
        if ((hasOtpKeyword && hasDigitCode) || otpIsYourOtpRegex.containsMatchIn(content)) {
            return Category.OTP
        }

        // 2. Transaction detection.
        val isPromotion = promoKeywords.any { kw ->
            when {
                kw == "data" && contentLower.contains("data wallet") -> false
                (kw == "recharge" || kw == "validity") &&
                    (contentLower.contains("fastag") || senderUpper.contains("FASTAG")) -> false
                kw == "nfo" -> nfoWordRegex.containsMatchIn(content)
                else -> contentLower.contains(kw)
            }
        }

        val isFutureTransaction = willBeDebitedCreditedRegex.containsMatchIn(contentLower) ||
            scheduledRegex.containsMatchIn(contentLower) ||
            initiatedRegex.containsMatchIn(contentLower)

        val isRequestNotification = (contentLower.contains("request") &&
            (contentLower.contains("receipt") || contentLower.contains("received") ||
                contentLower.contains("recd") || contentLower.contains("cancel") || contentLower.contains("redemption"))) ||
            (contentLower.contains("feedback") && contentLower.contains("important")) ||
            (contentLower.contains("ack") && contentLower.contains("receipt"))

        val hasAmount = amountRegex.containsMatchIn(content)

        if (suffixCategory == Category.TRANSACTIONAL) return Category.TRANSACTIONAL

        if (hasAmount &&
            (transactionKeywords.any { contentLower.contains(it) } ||
                bankSenders.any { senderLower.contains(it) } ||
                content.contains("Pluxee", ignoreCase = true) ||
                content.contains("FASTag", ignoreCase = true) ||
                senderUpper.contains("FASTAG"))
        ) {
            val isBillNotification = (contentLower.contains("due") || contentLower.contains("bill")) &&
                !contentLower.contains("paid") && !contentLower.contains("debited")
            val isMandateNotification = contentLower.contains("mandate registered") ||
                (contentLower.contains("mandate") && contentLower.contains("creation"))

            if (!isBillNotification && !isMandateNotification && !isFutureTransaction && !isPromotion && !isRequestNotification) {
                return Category.TRANSACTIONAL
            }
        }

        if (!isFutureTransaction && !isRequestNotification && !isPromotion) {
            if (contentLower.contains("sip") &&
                (contentLower.contains("processed") || contentLower.contains("due") || contentLower.contains("installment"))
            ) {
                return Category.TRANSACTIONAL
            }
            if (contentLower.contains("units") &&
                (contentLower.contains("nav") || contentLower.contains("allotted") || contentLower.contains("credited"))
            ) {
                return Category.TRANSACTIONAL
            }
            if (contentLower.contains("folio")) return Category.TRANSACTIONAL
            if (contentLower.contains("mutual fund") || contentLower.contains(" mf ")) return Category.TRANSACTIONAL
        }

        // 3. Updates.
        if (suffixCategory == Category.UPDATES) return Category.UPDATES
        if (updateKeywords.any { contentLower.contains(it) }) return Category.UPDATES

        // 4. Promotional.
        if (suffixCategory == Category.PROMOTIONAL) return Category.PROMOTIONAL
        // Same 'nfo'-inside-"info" word-boundary fix as the isPromotion check
        // above — a separate keyword scan, not a reuse of that result.
        if (promoKeywords.any { kw -> if (kw == "nfo") nfoWordRegex.containsMatchIn(content) else contentLower.contains(kw) }) {
            return Category.PROMOTIONAL
        }
        if (contentLower.contains("unsubscribe") || contentLower.contains("opt-out") || contentLower.contains("t&c")) {
            return Category.PROMOTIONAL
        }

        // Personal: only plain 10-digit senders.
        val cleanedNumber = sender.replaceFirst(Regex("^\\+?91"), "").replace(Regex("\\D"), "")
        if (Regex("^\\d{10}$").matches(cleanedNumber)) return Category.PERSONAL

        return Category.UPDATES
    }
}
