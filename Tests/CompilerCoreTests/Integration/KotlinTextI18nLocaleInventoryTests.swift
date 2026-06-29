#if canImport(Testing)
import Foundation
import Testing

// MARK: - STDLIB-I18N-COMMON-001: kotlin.text / common formatting and locale inventory
//
// This file documents which Kotlin common-scope i18n / locale APIs are implemented
// in the KSwiftK runtime and which are absent (gaps).
//
// Implemented (common scope, backed by runtime functions):
//   - String.lowercase()                   → kk_string_lowercase_flat
//   - String.uppercase()                   → kk_string_uppercase_flat
//   - String.lowercase(Locale)             → kk_string_lowercase_locale_flat
//   - String.uppercase(Locale)             → kk_string_uppercase_locale_flat
//   - String.compareTo(String, Locale)     → kk_string_compareTo_locale_flat
//   - String.toInt(radix)                  → kk_string_toInt_radix  (throwing)
//   - String.toIntOrNull()                 → kk_string_toIntOrNull  (no-radix variant)
//   - String.toIntOrNull(radix)            → kk_string_toIntOrNull_radix
//   - String.format(format, vararg args)   → kk_string_format_flat  (platform fmt, no locale overload)
//   - String.Companion.format(locale, format, vararg args) → kk_string_format_locale_flat
//   - Char.uppercase()                     → kk_char_uppercase  (returns String per Kotlin spec)
//   - Char.uppercase(Locale)               → kk_char_uppercase_locale
//   - Char.lowercase()                     → kk_char_lowercase  (returns String per Kotlin spec)
//   - Char.lowercase(Locale)               → kk_char_lowercase_locale
//   - Char.titlecase()                     → kk_char_titlecase
//   - Char.directionality                  → kk_char_directionality  (CharDirectionality enum)
//
// Gaps (absent in common scope):
//   - String.format(locale, vararg args)  — locale-parameterised receiver overload absent
//   - NumberFormat (java.text) is JVM/platform only, not common multiplatform

@Suite struct KotlinTextI18nLocaleInventoryTests {

    // MARK: - String.lowercase() / String.uppercase() — no locale (common)

    @Test func testStringLowercaseNoLocale() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "Hello WORLD"
            val lower = s.lowercase()
            println(lower)
        }
        """)
    }

    @Test func testStringUppercaseNoLocale() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "hello world"
            val upper = s.uppercase()
            println(upper)
        }
        """)
    }

    // MARK: - String.lowercase(Locale) / String.uppercase(Locale)

    @Test func testStringLowercaseWithLocale_enUS() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val locale = Locale("en", "US")
            val s = "HELLO WORLD"
            val lower = s.lowercase(locale)
            println(lower)
        }
        """)
    }

    @Test func testStringUppercaseWithLocale_enUS() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val locale = Locale("en", "US")
            val s = "hello world"
            val upper = s.uppercase(locale)
            println(upper)
        }
        """)
    }

    @Test func testStringLowercaseWithLocale_trTR() throws {
        // Turkish locale: dotted-I (I) lowercases to 'i' in tr-TR context
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val tr = Locale("tr", "TR")
            val result = "I".lowercase(tr)
            println(result)
        }
        """)
    }

    @Test func testStringUppercaseWithLocale_trTR() throws {
        // Turkish locale: 'i' uppercases to 'I' with locale context
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val tr = Locale("tr", "TR")
            val result = "i".uppercase(tr)
            println(result)
        }
        """)
    }

    // MARK: - String.compareTo with Locale

    @Test func testStringCompareToWithLocale() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val locale = Locale("en", "US")
            val cmp = "apple".compareTo("banana", locale)
            println(cmp)
        }
        """)
    }

    // MARK: - String.toInt(radix) — throwing variant

    @Test func testStringToIntRadix2() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val n = "1010".toInt(2)
            println(n)
        }
        """)
    }

    @Test func testStringToIntRadix16() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val n = "ff".toInt(16)
            println(n)
        }
        """)
    }

    @Test func testStringToIntRadixInvalidThrows() throws {
        // radix outside 2..36 must throw IllegalArgumentException
        try assertKotlinCompilesToKIR("""
        fun main() {
            try {
                val n = "10".toInt(1)
            } catch (e: IllegalArgumentException) {
                println("caught: " + e.message)
            }
        }
        """)
    }

    @Test func testStringToIntRadixBadInputThrows() throws {
        // input not representable in given radix must throw NumberFormatException
        try assertKotlinCompilesToKIR("""
        fun main() {
            try {
                val n = "xyz".toInt(10)
            } catch (e: NumberFormatException) {
                println("caught")
            }
        }
        """)
    }

    // MARK: - String.toIntOrNull() / String.toIntOrNull(radix)

    @Test func testStringToIntOrNullValid() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val n: Int? = "42".toIntOrNull()
            println(n)
        }
        """)
    }

    @Test func testStringToIntOrNullInvalid() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val n: Int? = "not_a_number".toIntOrNull()
            println(n)
        }
        """)
    }

    @Test func testStringToIntOrNullRadixValid() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val n: Int? = "ff".toIntOrNull(16)
            println(n)
        }
        """)
    }

    @Test func testStringToIntOrNullRadixInvalid() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val n: Int? = "xz".toIntOrNull(16)
            println(n)
        }
        """)
    }

    // MARK: - String.format (no-locale overload — implemented)

    @Test func testStringFormatNoLocale() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val result = String.format("Hello, %s! You are %d years old.", "Alice", 30)
            println(result)
        }
        """)
    }

    @Test func testStringFormatFloatSpecifier() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val result = String.format("Pi is approximately %.2f", 3.14159)
            println(result)
        }
        """)
    }

    @Test func testStringCompanionFormatLocaleSpecifier() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val locale = Locale("de", "DE")
            val result = String.format(locale, "Pi is approximately %.1f", 3.5)
            println(result)
        }
        """)
    }

    // MARK: - Char.uppercase() / Char.lowercase() — no locale (common)

    @Test func testCharUppercaseNoLocale() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val c = 'a'
            val upper = c.uppercase()
            println(upper)
        }
        """)
    }

    @Test func testCharUppercaseWithLocale_trTR() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val locale = Locale("tr", "TR")
            val upper = 'i'.uppercase(locale)
            println(upper)
        }
        """)
    }

    @Test func testCharLowercaseNoLocale() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val c = 'Z'
            val lower = c.lowercase()
            println(lower)
        }
        """)
    }

    @Test func testCharLowercaseWithLocale_trTR() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val locale = Locale("tr", "TR")
            val lower = 'I'.lowercase(locale)
            println(lower)
        }
        """)
    }

    @Test func testCharTitlecase() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val c = 'a'
            val title = c.titlecase()
            println(title)
        }
        """)
    }

    // MARK: - Char classification helpers used in i18n context

    @Test func testCharIsUpperCase() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val result = 'A'.isUpperCase()
            println(result)
        }
        """)
    }

    @Test func testCharIsLowerCase() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val result = 'a'.isLowerCase()
            println(result)
        }
        """)
    }

    @Test func testCharDirectionalityEnumSurface() throws {
        try assertKotlinCompilesToKIR("""
        import kotlin.text.CharDirectionality

        fun main() {
            val direction: CharDirectionality = 'A'.directionality
            println(direction == CharDirectionality.LEFT_TO_RIGHT)
        }
        """)
    }

    // MARK: - Locale construction edge cases

    @Test func testLocaleByIdentifier() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val locale = Locale("en_US")
            println(locale.language)
            println(locale.country)
        }
        """)
    }

    @Test func testLocaleByLanguageAndCountry() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val locale = Locale("de", "DE")
            println(locale.language)
            println(locale.country)
        }
        """)
    }

    @Test func testLocaleGetDefault() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val def = Locale.getDefault()
            println(def.language)
        }
        """)
    }

    @Test func testLocaleSetDefault() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val fr = Locale("fr", "FR")
            Locale.setDefault(fr)
            val def = Locale.getDefault()
            println(def.language)
        }
        """)
    }

    @Test func testLocaleDisplayLanguage() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val locale = Locale("en", "US")
            println(locale.displayLanguage)
        }
        """)
    }

    @Test func testLocaleEquality() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val a = Locale("en", "US")
            val b = Locale("en", "US")
            val same = a.equals(b)
            println(same)
        }
        """)
    }

    @Test func testLocaleHashCode() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val locale = Locale("en", "US")
            val hash = locale.hashCode()
            println(hash)
        }
        """)
    }
}
#endif
