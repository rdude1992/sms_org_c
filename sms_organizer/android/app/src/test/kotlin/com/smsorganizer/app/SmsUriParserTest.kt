package com.smsorganizer.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SmsUriParserTest {

    @Test
    fun splitsBodyQueryOffAddress() {
        val p = SmsUriParser.parseSchemeSpecificPart("+911234567890?body=Hello%20there")
        assertEquals("+911234567890", p.address)
        assertEquals("Hello there", p.body)
    }

    @Test
    fun ampersandInsideEncodedBodyIsKept() {
        val p = SmsUriParser.parseSchemeSpecificPart("12345?body=Tom%20%26%20Jerry")
        assertEquals("12345", p.address)
        assertEquals("Tom & Jerry", p.body)
    }

    @Test
    fun plainAddressHasNoBody() {
        val p = SmsUriParser.parseSchemeSpecificPart("9876543210")
        assertEquals("9876543210", p.address)
        assertNull(p.body)
    }

    @Test
    fun multipleRecipientsNormalisedToSemicolons() {
        assertEquals("111;222", SmsUriParser.parseSchemeSpecificPart("111,222").address)
    }

    @Test
    fun blankInputIsEmpty() {
        val p = SmsUriParser.parseSchemeSpecificPart("")
        assertNull(p.address)
        assertNull(p.body)
    }
}
