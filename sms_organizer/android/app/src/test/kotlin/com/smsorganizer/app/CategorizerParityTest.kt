package com.smsorganizer.app

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

/**
 * Runs the native classifier over the same vectors as the Dart test
 * (test/categorization_service_test.dart), so Categorizer.kt and
 * categorization_service.dart can't drift apart unnoticed.
 */
class CategorizerParityTest {

    private fun fixture(): File {
        // Gradle runs unit tests with the module dir (android/app) as cwd.
        val candidates = listOf(
            File("../../test/fixtures/categorization_cases.tsv"),
            File("test/fixtures/categorization_cases.tsv")
        )
        return candidates.firstOrNull { it.exists() }
            ?: error("categorization_cases.tsv not found from ${File(".").absolutePath}")
    }

    @Test
    fun matchesSharedFixture() {
        val failures = mutableListOf<String>()
        var count = 0
        fixture().readLines()
            .filter { it.isNotBlank() && !it.startsWith("#") }
            .forEach { line ->
                val parts = line.split('\t')
                val expected = Categorizer.Category.valueOf(parts[0].uppercase())
                val sender = parts[1]
                val body = parts.drop(2).joinToString("\t")
                val actual = Categorizer.categorize(sender, body)
                count++
                if (actual != expected) failures += "[$sender] \"$body\": expected $expected, got $actual"
            }
        check(count > 0) { "fixture had no cases" }
        assertEquals("Mismatches:\n" + failures.joinToString("\n"), 0, failures.size)
    }
}
