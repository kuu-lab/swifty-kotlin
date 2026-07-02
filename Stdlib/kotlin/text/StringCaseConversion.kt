package kotlin.text

// String case conversion functions
// MIGRATION-TEXT-005
//
// capitalize() and replaceFirstChar() are compiled via BundledKotlinStdlib.
// lowercase(), uppercase(), and locale variants are wired via native stubs backed by
// bridge functions: __string_lowercase, __string_uppercase, __string_lowercase_locale,
// __string_uppercase_locale. Future: wire these through the bundled pipeline.

/**
 * Returns a copy of this string converted to lower case.
 *
 * NOTE: Backed by __string_lowercase bridge (MIGRATION-TEXT-005).
 */
// public actual fun String.lowercase(): String = __string_lowercase(this)

/**
 * Returns a copy of this string converted to upper case.
 *
 * NOTE: Backed by __string_uppercase bridge (MIGRATION-TEXT-005).
 */
// public actual fun String.uppercase(): String = __string_uppercase(this)

/**
 * Returns a copy of this string converted to lower case using the specified locale.
 *
 * NOTE: Backed by __string_lowercase_locale bridge (MIGRATION-TEXT-005).
 */
// public actual fun String.lowercase(locale: java.util.Locale): String = __string_lowercase_locale(this, locale)

/**
 * Returns a copy of this string converted to upper case using the specified locale.
 *
 * NOTE: Backed by __string_uppercase_locale bridge (MIGRATION-TEXT-005).
 */
// public actual fun String.uppercase(locale: java.util.Locale): String = __string_uppercase_locale(this, locale)

/**
 * Returns a copy of this string having its first letter upper-cased,
 * or the original string if it's empty or already starts with an upper case letter.
 *
 * Deprecated in Kotlin 1.5+. Use replaceFirstChar instead.
 */
@Deprecated("Use replaceFirstChar instead.",
    replaceWith = ReplaceWith("replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.getDefault()) else it.toString() }"))
public fun String.capitalize(): String {
    if (isEmpty()) return this
    val sb = StringBuilder()
    sb.append(this[0].uppercase())
    var i = 1
    while (i < length) { sb.append(this[i]); i += 1 }
    return sb.toString()
}

/**
 * Returns a copy of this string having its first character replaced with the result of the
 * specified [transform] function applied to the first character of this string.
 *
 * NOTE: substring() cannot be used from bundled Kotlin source because the call lowering path
 * does not fill in the extra end/hasEnd parameters that kk_string_substring expects.
 */
public fun String.replaceFirstChar(transform: (Char) -> Char): String {
    if (isEmpty()) return this
    val sb = StringBuilder()
    sb.append(transform(this[0]))
    var i = 1
    while (i < length) { sb.append(this[i]); i += 1 }
    return sb.toString()
}
