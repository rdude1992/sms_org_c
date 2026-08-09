package com.smsorganizer.app

/**
 * Native mirror of extractAmount()/extractMerchant()/extractAccountNumber()/
 * getTransactionType() in lib/utils/sms_extractors.dart, used only to build
 * the notification's compact "amount / payee / account" summary for
 * transactional messages — see IncomingSmsNotifier.formatTransactionMessage.
 * The canonical extraction (and what's parsed/stored in-app) is still the
 * Dart version; keep this in sync manually if that one changes, same
 * caveat as OtpExtractor/Categorizer.
 */
object TransactionExtractor {
    enum class Direction { CREDIT, DEBIT, REVERSAL, UNKNOWN }

    data class Details(
        val amount: Double?,
        val direction: Direction,
        val merchant: String?,
        val account: String?
    )

    fun extract(content: String): Details {
        return Details(
            amount = extractAmount(content),
            direction = extractDirection(content),
            merchant = extractMerchant(content),
            account = extractAccount(content)
        )
    }

    // ---- amount ----

    private val amountPatterns = listOf(
        Regex("(?:rs\\.?|inr|₹)\\s*([\\d,]+(?:\\.\\d{1,2})?)", RegexOption.IGNORE_CASE),
        Regex("([\\d,]+(?:\\.\\d{1,2})?)\\s*(?:rs|rupees|inr)", RegexOption.IGNORE_CASE)
    )
    private val pluxeeSodexoRegex = Regex("Pluxee|Sodexo", RegexOption.IGNORE_CASE)
    private val pluxeeWithRegex = Regex("with\\s+([\\d,]+(?:\\.\\d{1,2})?)\\s+towards", RegexOption.IGNORE_CASE)
    private val pluxeePurchaseRegex = Regex("purchase\\s+of\\s+([\\d,]+(?:\\.\\d{1,2})?)", RegexOption.IGNORE_CASE)

    private fun extractAmount(content: String): Double? {
        val contentLower = content.lowercase()
        for (pattern in amountPatterns) {
            for (match in pattern.findAll(content)) {
                val group1 = match.groups[1]?.value ?: continue
                val amount = group1.replace(",", "").toDoubleOrNull() ?: continue
                if (amount <= 0 || amount >= 10_000_000) continue
                if (amount in 1900.0..2100.0 && !contentLower.contains("rs") && !content.contains("₹")) {
                    continue // Likely a year, not an amount.
                }
                return amount
            }
        }

        if (pluxeeSodexoRegex.containsMatchIn(content)) {
            val group1 = pluxeeWithRegex.find(content)?.groups?.get(1)?.value
                ?: pluxeePurchaseRegex.find(content)?.groups?.get(1)?.value
            if (group1 != null) return group1.replace(",", "").toDoubleOrNull()
        }
        return null
    }

    // ---- direction ----

    private val creditedToOtherRegex =
        Regex("credited\\s+to\\s+(?!your\\b|a\\/c|account)[A-Za-z]", RegexOption.IGNORE_CASE)
    private val neftImpsRegex = Regex("\\b(neft|imps|money\\s+transfer)\\b", RegexOption.IGNORE_CASE)
    private val sentWordRegex = Regex("\\bsent\\b", RegexOption.IGNORE_CASE)

    private fun extractDirection(content: String): Direction {
        val lower = content.lowercase()

        if (lower.contains("reversed") || lower.contains("declined") || lower.contains("failed") ||
            lower.contains("trxn reversed")
        ) {
            return Direction.REVERSAL
        }

        // Investment debit, high priority: "units allotted"/"SIP processed
        // with NAV" mean money LEFT the user's bank account even though the
        // message says "credited" (to the fund/folio, not to the user's cash).
        if (lower.contains("allotted") || lower.contains("alloted") ||
            (lower.contains("sip") && lower.contains("processed") && lower.contains("nav")) ||
            (lower.contains("units") && lower.contains("credited"))
        ) {
            return Direction.DEBIT
        }

        // An outgoing NEFT/IMPS confirmation phrased from the *recipient's*
        // side ("credited to Priya Sharma"), not the user's own account.
        if (creditedToOtherRegex.containsMatchIn(content) && neftImpsRegex.containsMatchIn(content)) {
            return Direction.DEBIT
        }

        if (lower.contains("credited") || lower.contains("received") || lower.contains("deposited") ||
            lower.contains("added to") || lower.contains("successfully added") ||
            lower.contains("refund on") || lower.contains("refund processed") ||
            lower.contains("redemption") || lower.contains("redeemed")
        ) {
            return Direction.CREDIT
        }

        // Exclude "due"/"bill" reminders that haven't actually been paid yet.
        if (lower.contains("due") || lower.contains("bill generated") || lower.contains("to be paid")) {
            if (!lower.contains("paid") && !lower.contains("debited") && !lower.contains("auto-debited")) {
                return Direction.UNKNOWN
            }
        }

        if (lower.contains("debited") || lower.contains("deducted") || lower.contains("spent") ||
            lower.contains("paid") || lower.contains("withdrawn") || lower.contains("purchase") ||
            lower.contains("switch in") || lower.contains("sent to") || lower.contains("transfer to") ||
            lower.contains("installment") || lower.contains("allotted") ||
            lower.contains("succeeded") || lower.contains("processed successfully") ||
            lower.contains("money transfer")
        ) {
            return Direction.DEBIT
        }

        if (sentWordRegex.containsMatchIn(content)) {
            return Direction.DEBIT
        }

        return Direction.UNKNOWN
    }

    // ---- merchant ----

    private val merchantPatterns = listOf(
        Regex("([a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+)"),
        Regex("(?:^|\\n)To\\s+([A-Za-z0-9\\s&./'-]{2,50}?)\\s*(?:\\n|$)", RegexOption.IGNORE_CASE),
        Regex("towards\\s+([A-Za-z0-9\\s&.'-]{2,40}?)(?:\\s*\\/|\\s+UMRN|\\n|$|\\.)", RegexOption.IGNORE_CASE),
        Regex(
            "(?:paid\\s+to|sent\\s+to|transfer\\s+to|at)\\s+([A-Za-z0-9\\s&.*_/'-]{2,30}?)" +
                "(?:\\s+(?:via|using|through|on|by)|$|\\.|\\n)",
            RegexOption.IGNORE_CASE
        ),
        Regex(
            "(?:received\\s+from|credit\\s+from)\\s+([A-Za-z0-9\\s&.'-]{2,30}?)" +
                "(?:\\s+(?:via|using|through|on|by)|$|\\.)",
            RegexOption.IGNORE_CASE
        ),
        Regex(
            "(?:spent\\s+at|used\\s+at|purchase\\s+at)\\s+([A-Za-z0-9\\s&.'-]{2,30}?)(?:\\s+on|$|\\.)",
            RegexOption.IGNORE_CASE
        ),
        Regex("Bill\\s+Paid[:!]?\\s*\\n?\\s*([A-Za-z0-9]+)\\s+Bill\\b", RegexOption.IGNORE_CASE),
        Regex("Your\\s+([A-Za-z0-9\\s]+?)\\s+bill\\s+payment", RegexOption.IGNORE_CASE),
        Regex("\\bto\\s+([A-Za-z0-9\\s&.\\-]{2,40}?)\\s+UPI\\b", RegexOption.IGNORE_CASE),
        Regex("\\bto\\s+([A-Za-z0-9_.\\s&-]{2,40}?)\\s+succeeded\\b", RegexOption.IGNORE_CASE),
        Regex("for\\s+purchase\\s+of\\s+([A-Za-z\\s]+?)\\s+is\\b", RegexOption.IGNORE_CASE)
    )
    private val excludeList = listOf(
        "your", "the", "account", "card", "bank", "ac", "a/c", "ending", "nav", "folio", "units", "rs", "inr"
    )
    private val commonMerchants = listOf(
        "swiggy", "zomato", "uber", "ola", "amazon", "flipkart", "myntra", "netflix",
        "spotify", "hotstar", "jiomart", "bigbasket", "blinkit", "zepto", "bookmyshow", "makemytrip"
    )
    private val viaUpiRegex = Regex("\\s+via\\s+upi", RegexOption.IGNORE_CASE)

    private fun extractMerchant(content: String): String? {
        for (pattern in merchantPatterns) {
            val raw = pattern.find(content)?.groups?.get(1)?.value?.trim() ?: continue
            if (raw.isEmpty()) continue
            val merchant = raw.replace(viaUpiRegex, "")
            if (merchant.isEmpty()) continue
            val merchantLower = merchant.lowercase()
            if (excludeList.none { merchantLower.startsWith(it) }) {
                return merchant.replaceFirstChar { it.uppercase() }
            }
        }

        val contentLower = content.lowercase()
        for (m in commonMerchants) {
            if (contentLower.contains(m)) return m.replaceFirstChar { it.uppercase() }
        }

        if (pluxeeSodexoRegex.containsMatchIn(content)) return "Pluxee"
        return null
    }

    // ---- account ----

    private val accountExplicitPatterns = listOf(
        Regex(
            "(?:bank|a\\/c|acct|account|card)\\s*(?:no\\.?|ending(?:\\s+with)?|xxxx?)?\\s*[:\\s.-]*" +
                "(?:xx|x{1,4}|\\*{1,4})(\\d{4})",
            RegexOption.IGNORE_CASE
        ),
        Regex(
            "(?:debited from|credited to|debited\\s+from|credited\\s+to)\\s+(?:.*?)\\s+" +
                "(?:xx|x{1,4}|\\*{1,4})(\\d{4})",
            RegexOption.IGNORE_CASE
        ),
        Regex("(?:SB|SA|CA)[-.\\s]*(?:xx|x{1,4}|\\*{1,4})[-\\s]*(\\d{4})", RegexOption.IGNORE_CASE),
        Regex("card\\s+ending(?:\\s+with)?\\s+(\\d{4})\\b", RegexOption.IGNORE_CASE)
    )
    private val upiRefRegex = Regex("UPI-[a-zA-Z0-9-]+\\d{4}", RegexOption.IGNORE_CASE)
    private val refNoRegex = Regex("Ref\\s*no\\s*\\d+", RegexOption.IGNORE_CASE)
    private val genericAccountRegex = Regex("(?:xx|x{1,}|\\*{1,})[-\\s]*(\\d{4})", RegexOption.IGNORE_CASE)
    private val bareAccountRegex = Regex(
        "(?:a\\/c|acct|account)\\s*(?:no\\.?)?\\s+(\\d{4})\\b|\\bcard\\s+(\\d{4})\\b",
        RegexOption.IGNORE_CASE
    )

    private fun extractAccount(content: String): String? {
        for (pattern in accountExplicitPatterns) {
            val digits = pattern.find(content)?.groups?.get(1)?.value
            if (!digits.isNullOrEmpty()) return "XX$digits"
        }

        // Remove UPI reference / ref-no patterns before the generic XX pass,
        // so they don't get mistaken for a masked account number.
        var safeContent = content.replace(upiRefRegex, "UPI-REFERENCE-REMOVED")
        safeContent = safeContent.replace(refNoRegex, "REF-REMOVED")

        val genericDigits = genericAccountRegex.find(safeContent)?.groups?.get(1)?.value
        if (!genericDigits.isNullOrEmpty()) return "XX$genericDigits"

        val bareMatch = bareAccountRegex.find(safeContent)
        if (bareMatch != null) {
            val digits = bareMatch.groups[1]?.value ?: bareMatch.groups[2]?.value
            if (!digits.isNullOrEmpty()) return "XX$digits"
        }

        if (pluxeeSodexoRegex.containsMatchIn(content) &&
            (content.contains("Card") || content.contains("card"))
        ) {
            return "Pluxee Card"
        }
        return null
    }
}
