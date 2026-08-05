package com.smsorganizer.app

/**
 * Minimal native mirror of lib/services/categorization_service.dart
 * (regex sourced from lib/utils/regex_patterns.dart). Used only to decide
 * which notification channel to post on and whether that category is
 * muted, for the case where no Flutter engine is running to do the real
 * classification that drives the in-app UI.
 *
 * Keep this in sync manually if you tune the regex on the Dart side —
 * there's no code sharing between Kotlin and Dart here, so drift between
 * "category shown in-app" and "category used for the notification" is
 * possible if only one side gets updated.
 */
object Categorizer {
    enum class Category(val prefKey: String) {
        PERSONAL("personal"),
        PROMOTIONAL("promotional"),
        TRANSACTIONAL("transactional"),
        OTP("otp"),
    }

    private val otpRegex = Regex(
        "\\b(otp|one[\\s-]?time password|verification code|security code)\\b",
        RegexOption.IGNORE_CASE
    )
    private val transactionalRegex = Regex(
        "\\b(debited|credited|withdrawn|spent|txn|transaction|purchase of|paid to|received from|a/c|acc(?:ount)? no|available balance|avl bal|upi|imps|neft|rtgs|emi)\\b",
        RegexOption.IGNORE_CASE
    )
    private val amountRegex = Regex(
        "(?:rs\\.?|inr|₹)\\s*[\\d,]+(?:\\.\\d{1,2})?",
        RegexOption.IGNORE_CASE
    )
    private val promoRegex = Regex(
        "\\b(sale|offer|discount|cashback\\s+offer|deal|coupon|flat\\s?\\d+%|win\\s+free|subscribe|unsubscribe|limited period|hurry|shop now|t&c apply)\\b",
        RegexOption.IGNORE_CASE
    )

    fun categorize(body: String): Category {
        if (otpRegex.containsMatchIn(body)) return Category.OTP
        // Same false-positive guard as the Dart version: require an actual
        // amount alongside a transaction keyword, not just generic bank
        // chatter ("update your KYC") that happens to mention "account".
        if (transactionalRegex.containsMatchIn(body) && amountRegex.containsMatchIn(body)) {
            return Category.TRANSACTIONAL
        }
        if (promoRegex.containsMatchIn(body)) return Category.PROMOTIONAL
        return Category.PERSONAL
    }
}
