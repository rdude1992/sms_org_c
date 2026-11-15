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
    private val digitCodeRegex = Regex("\\b\\d{4,8}\\b")
    private val willBeDebitedCreditedRegex = Regex("will\\s+be\\s+(?:debited|credited)", RegexOption.IGNORE_CASE)
    private val scheduledRegex = Regex("scheduled", RegexOption.IGNORE_CASE)
    private val initiatedRegex = Regex("initiated", RegexOption.IGNORE_CASE)
    private val nfoWordRegex = Regex("\\bnfo\\b", RegexOption.IGNORE_CASE)
    private val pendingRequestRegex =
        Regex("has\\s+requested\\s+(?:Rs\\.?|INR|₹|money)", RegexOption.IGNORE_CASE)

    // Mirrors CategorizationService._otpWarning / _explicitOtp / _moneyMoved /
    // _strongBankAlert / _paymentReceived — see the Dart side for rationale.
    private val otpWarningRegex = Regex(
        "\\b(?:never|do\\s+not|don'?t|pls\\s+do\\s+not|please\\s+do\\s+not)\\s+(?:share|disclose|tell|give)\\b[^.!\\n]*"
    )
    private val explicitOtpRegex = Regex(
        "\\b(?:otp|one time password|verification code|passcode)\\b[^.]{0,40}?\\b\\d{4,8}\\b" +
            "|\\b\\d{4,8}\\b[^.]{0,30}?\\b(?:otp|one time password|verification code)\\b"
    )
    private val moneyMovedRegex =
        Regex("\\b(?:debited|credited|spent|withdrawn|paid|sent|received|transferred)\\b")
    private val strongBankAlertRegex = Regex("\\b(?:debited|credited)\\b")
    private val paymentReceivedRegex =
        Regex("(?:payment|amount)[^.]{0,60}\\b(?:received|credited)\\b|received\\s+towards")
    private val phonePrefixRegex = Regex("^\\+?91")
    private val nonDigitRegex = Regex("\\D")
    private val tenDigitsRegex = Regex("^\\d{10}$")

    // Mirrors CategorizationService._boundaryKeywords.
    private val boundaryKeywords: Map<String, Regex> =
        listOf(
            "win", "bus", "sip", "nav", "train", "order", "free", "deal", "sale",
            "data", "cab", "ride", "grab", "limit", "points", "card", "units"
        ).associateWith { Regex("\\b$it(?:s|es)?\\b") } +
            ("ack" to Regex("\\back(?:nowledg\\w*)?\\b"))

    private fun hasKeyword(lower: String, kw: String): Boolean =
        boundaryKeywords[kw]?.containsMatchIn(lower) ?: lower.contains(kw)

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

    fun isPhoneNumberAddress(sender: String): Boolean =
        tenDigitsRegex.matches(sender.replaceFirst(phonePrefixRegex, "").replace(nonDigitRegex, ""))

    fun categorize(sender: String, content: String): Category {
        val contentLower = content.lowercase()
        val senderLower = sender.lowercase()
        val senderUpper = sender.uppercase()

        val otpScan = contentLower.replace(otpWarningRegex, " ")
        val hasOtpKeyword = otpKeywords.any { otpScan.contains(it) }
        val hasDigitCode = digitCodeRegex.containsMatchIn(otpScan)
        val hasAmount = amountRegex.containsMatchIn(content)
        val isOtp = otpScan.contains("is your otp") ||
            explicitOtpRegex.containsMatchIn(otpScan) ||
            (hasOtpKeyword && hasDigitCode && !(hasAmount && moneyMovedRegex.containsMatchIn(otpScan)))

        if (isPhoneNumberAddress(sender) && !suffixRegex.containsMatchIn(sender)) {
            if (isOtp) return Category.OTP
            if (hasAmount && strongBankAlertRegex.containsMatchIn(contentLower) &&
                (contentLower.contains("a/c") || contentLower.contains("account") || contentLower.contains("upi"))
            ) {
                return Category.TRANSACTIONAL
            }
            return Category.PERSONAL
        }

        val isPaymentReceived = paymentReceivedRegex.containsMatchIn(contentLower)

        if (contentLower.contains("view statement") ||
            contentLower.contains("account statement") ||
            contentLower.contains("a/c statement") ||
            contentLower.contains("download statement") ||
            contentLower.contains("statement of account") ||
            contentLower.contains("statement for folio") ||
            (contentLower.contains("stmt") &&
                (contentLower.contains("view") || contentLower.contains("click") || contentLower.contains("check"))) ||
            (contentLower.contains("redemption transaction") && contentLower.contains("processed")) ||
            (contentLower.contains("due") && !isPaymentReceived &&
                (contentLower.contains("debit") || contentLower.contains("payment") || hasKeyword(contentLower, "sip"))) ||
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

        if (contentLower.contains("reported your fund bal")) return Category.UPDATES

        val suffixCategory: Category? = suffixRegex.find(sender)?.groupValues?.get(1)?.uppercase()?.let { suffix ->
            when (suffix) {
                "P" -> Category.PROMOTIONAL
                "S", "G" -> Category.UPDATES
                "T" -> Category.TRANSACTIONAL
                else -> null
            }
        }

        if (isOtp) return Category.OTP

        val isPromotion = promoKeywords.any { kw ->
            when {
                kw == "data" && contentLower.contains("data wallet") -> false
                (kw == "recharge" || kw == "validity") &&
                    (contentLower.contains("fastag") || senderUpper.contains("FASTAG")) -> false
                kw == "nfo" -> nfoWordRegex.containsMatchIn(content)
                else -> hasKeyword(contentLower, kw)
            }
        }

        val isFutureTransaction = willBeDebitedCreditedRegex.containsMatchIn(contentLower) ||
            scheduledRegex.containsMatchIn(contentLower) ||
            initiatedRegex.containsMatchIn(contentLower)

        val isPendingPaymentRequest =
            pendingRequestRegex.containsMatchIn(content) && contentLower.contains("from you")

        val isRequestNotification = (contentLower.contains("request") &&
            (contentLower.contains("receipt") || contentLower.contains("received") ||
                contentLower.contains("recd") || contentLower.contains("cancel") || contentLower.contains("redemption"))) ||
            (contentLower.contains("feedback") && contentLower.contains("important")) ||
            (hasKeyword(contentLower, "ack") && contentLower.contains("receipt")) ||
            isPendingPaymentRequest

        if (suffixCategory == Category.TRANSACTIONAL) return Category.TRANSACTIONAL

        val isEpfoContribution = contentLower.contains("contribution") &&
            (contentLower.contains("epfo") || contentLower.contains("provident fund") ||
                contentLower.contains("passbook balance"))

        if (hasAmount &&
            (transactionKeywords.any { hasKeyword(contentLower, it) } ||
                bankSenders.any { senderLower.contains(it) } ||
                content.contains("Pluxee", ignoreCase = true) ||
                content.contains("FASTag", ignoreCase = true) ||
                senderUpper.contains("FASTAG"))
        ) {
            val isBillNotification = (contentLower.contains("due") || contentLower.contains("bill")) &&
                !contentLower.contains("paid") && !contentLower.contains("debited") &&
                !isPaymentReceived && !isEpfoContribution
            val isMandateNotification = contentLower.contains("mandate registered") ||
                (contentLower.contains("mandate") && contentLower.contains("creation"))

            if (!isBillNotification && !isMandateNotification && !isFutureTransaction && !isPromotion && !isRequestNotification) {
                return Category.TRANSACTIONAL
            }
        }

        if (!isFutureTransaction && !isRequestNotification && !isPromotion) {
            if (hasKeyword(contentLower, "sip") &&
                (contentLower.contains("processed") || contentLower.contains("due") || contentLower.contains("installment"))
            ) {
                return Category.TRANSACTIONAL
            }
            if (hasKeyword(contentLower, "units") &&
                (contentLower.contains("nav") || contentLower.contains("allotted") || contentLower.contains("credited"))
            ) {
                return Category.TRANSACTIONAL
            }
            if (contentLower.contains("folio")) return Category.TRANSACTIONAL
            if (contentLower.contains("mutual fund") || contentLower.contains(" mf ")) return Category.TRANSACTIONAL
        }

        // 3. Updates.
        if (suffixCategory == Category.UPDATES) return Category.UPDATES
        if (updateKeywords.any { hasKeyword(contentLower, it) }) return Category.UPDATES

        // 4. Promotional.
        if (suffixCategory == Category.PROMOTIONAL) return Category.PROMOTIONAL
        if (promoKeywords.any { kw -> if (kw == "nfo") nfoWordRegex.containsMatchIn(content) else hasKeyword(contentLower, kw) }) {
            return Category.PROMOTIONAL
        }
        if (contentLower.contains("unsubscribe") || contentLower.contains("opt-out") || contentLower.contains("t&c")) {
            return Category.PROMOTIONAL
        }

        return Category.UPDATES
    }
}
