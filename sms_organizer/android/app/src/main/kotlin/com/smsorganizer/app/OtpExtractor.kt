package com.smsorganizer.app

/**
 * Native mirror of extractOtp() in lib/utils/sms_extractors.dart, used only
 * to back the notification's "Copy OTP" quick action so the code arrives
 * on the lock screen without opening the app. The canonical extraction
 * (and what's shown in-app) is still the Dart version — keep this in sync
 * manually if that one changes, same caveat as Categorizer.
 */
object OtpExtractor {
    private val withContextRegex =
        Regex("(?:otp|code|pin|passcode|password)[\\s:is-]*([A-Za-z0-9]{4,8})", RegexOption.IGNORE_CASE)
    private val digitsRegex = Regex("\\b\\d{4,6}\\b")
    private val hasDigitRegex = Regex("\\d")

    fun extract(content: String): String? {
        val contextMatch = withContextRegex.find(content)
        val candidate = contextMatch?.groupValues?.get(1)
        if (candidate != null && hasDigitRegex.containsMatchIn(candidate)) {
            return candidate
        }

        for (match in digitsRegex.findAll(content)) {
            val value = match.value
            val precededByNonOtpContext = Regex(
                "(?:rs\\.|rs|inr|₹|xx|\\*|ending|ac|no\\.|bal|balance)[\\s:.]*" + Regex.escape(value),
                RegexOption.IGNORE_CASE
            )
            if (!precededByNonOtpContext.containsMatchIn(content)) {
                return value
            }
        }
        return null
    }
}
