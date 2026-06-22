package kotlin.text

// String case conversion and locale functions migrated from Swift Runtime.
// MIGRATION-TEXT-005

/**
 * Returns a copy of this string converted to lower case using Unicode case mapping.
 *
 * Each character is converted through [Char.lowercase], so multi-character mappings
 * such as Latin capital I with dot are preserved.
 */
public fun String.lowercase(): String {
    if (isEmpty()) return this
    val sb = StringBuilder()
    var i = 0
    while (i < length) {
        sb.append(this[i].lowercase())
        i += 1
    }
    return sb.toString()
}

/**
 * Returns a copy of this string converted to upper case using Unicode case mapping.
 *
 * Each character is converted through [Char.uppercase], so multi-character mappings
 * such as sharp-s to "SS" are preserved.
 */
public fun String.uppercase(): String {
    if (isEmpty()) return this
    val sb = StringBuilder()
    var i = 0
    while (i < length) {
        sb.append(this[i].uppercase())
        i += 1
    }
    return sb.toString()
}

/**
 * Returns a copy of this string with the first character upper-cased.
 *
 * Deprecated by Kotlin, but still provided for compatibility.
 */
public fun String.capitalize(): String {
    if (isEmpty()) return this
    val sb = StringBuilder()
    sb.append(this[0].uppercase())
    var i = 1
    while (i < length) {
        sb.append(this[i])
        i += 1
    }
    return sb.toString()
}

/**
 * Returns a string having its first character replaced with [transform].
 *
 * KSwiftK currently models the transform as `(Char) -> Char` to match the existing
 * callable lowering support. The upstream Kotlin stdlib also has a CharSequence
 * returning overload; migrate that surface when function-type overloads support it.
 */
public fun String.replaceFirstChar(transform: (Char) -> Char): String {
    if (isEmpty()) return this
    val sb = StringBuilder()
    sb.append(transform(this[0]))
    var i = 1
    while (i < length) {
        sb.append(this[i])
        i += 1
    }
    return sb.toString()
}

/**
 * Returns a copy of this string converted to lower case using [locale].
 */
public fun String.lowercase(locale: java.util.Locale): String =
    this.__kk_lowercase_locale(locale)

/**
 * Returns a copy of this string converted to upper case using [locale].
 */
public fun String.uppercase(locale: java.util.Locale): String =
    this.__kk_uppercase_locale(locale)
