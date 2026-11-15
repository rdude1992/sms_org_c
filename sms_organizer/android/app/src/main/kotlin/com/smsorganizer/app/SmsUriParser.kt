package com.smsorganizer.app

import android.content.Intent
import java.net.URLDecoder

/**
 * Pulls recipient + body out of an sms:/smsto:/mms:/mmsto: intent.
 *
 * The scheme-specific part of "sms:+911234567890?body=Hi" is
 * "+911234567890?body=Hi", so the query must be split off by hand. Opaque URIs
 * have no getQueryParameter support. The still-encoded form is parsed and then
 * decoded once, so an "&" or "?" inside the body can't break the split.
 * The body can arrive as the `body` query
 * param, the de-facto `sms_body` extra, or EXTRA_TEXT.
 */
object SmsUriParser {
    data class Parsed(val address: String?, val body: String?)

    fun parse(intent: Intent?): Parsed {
        if (intent == null) return Parsed(null, null)
        val fromUri = parseSchemeSpecificPart(intent.data?.encodedSchemeSpecificPart)
        val body = fromUri.body
            ?: intent.getStringExtra("sms_body")
            ?: intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        return Parsed(fromUri.address, body)
    }

    /** Pure string logic, kept separate so it is unit-testable on the JVM. */
    fun parseSchemeSpecificPart(ssp: String?): Parsed {
        if (ssp.isNullOrBlank()) return Parsed(null, null)
        val q = ssp.indexOf('?')
        val rawAddress = if (q >= 0) ssp.substring(0, q) else ssp
        val query = if (q >= 0) ssp.substring(q + 1) else ""

        var body: String? = null
        if (query.isNotEmpty()) {
            for (pair in query.split('&')) {
                val eq = pair.indexOf('=')
                if (eq <= 0) continue
                if (pair.substring(0, eq).equals("body", ignoreCase = true)) {
                    body = decode(pair.substring(eq + 1))
                }
            }
        }
        // Leading "//" appears in "smsto://123" forms; separators between
        // multiple recipients are normalised to ";" (Android convention).
        val address = decode(rawAddress).removePrefix("//").trim()
            .replace(',', ';')
            .takeIf { it.isNotEmpty() }
        return Parsed(address, body?.takeIf { it.isNotEmpty() })
    }

    private fun decode(s: String): String = try {
        // In a URI a literal "+" is a real plus sign (phone numbers), not a
        // space. Protect it from URLDecoder's form-encoding rules.
        URLDecoder.decode(s.replace("+", "%2B"), "UTF-8")
    } catch (_: Exception) {
        s
    }
}
