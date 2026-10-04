package kotlin.text

import kotlin.internal.KsSymbolName
import kswiftk.internal.*

// String case conversion and locale functions migrated from Swift Runtime.
// MIGRATION-TEXT-005

// The runtime lowercases the whole string so that the context-sensitive Final_Sigma
// rule (capital sigma at the end of a word becomes final sigma) can see its neighbours.
@KsSymbolName("kk_string_lowercase")
private external fun String.__kkStringLowercase(): String

/**
 * Returns a copy of this string converted to lower case using Unicode case mapping.
 *
 * Multi-character mappings such as Latin capital I with dot are preserved, and a
 * capital sigma at the end of a word maps to final sigma.
 */
public fun String.lowercase(): String = this.__kkStringLowercase()

/**
 * Returns a copy of this string converted to upper case using Unicode case mapping.
 *
 * Each character is converted through [Char.uppercase], so multi-character mappings
 * such as sharp-s to "SS" are preserved.
 */
public fun String.uppercase(): String {
    if (this.length == 0) return this
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
    if (this.length == 0) return this
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
 * Returns a copy of this string with the first character lower-cased.
 *
 * Deprecated by Kotlin, but still provided for compatibility.
 */
@Deprecated(
    "Use replaceFirstChar instead.",
    ReplaceWith("replaceFirstChar { it.lowercase() }")
)
@DeprecatedSinceKotlin(warningSince = "1.5")
public fun String.decapitalize(): String {
    if (this.length == 0) return this
    val first = this[0]
    if (first.isLowerCase()) return this

    val sb = StringBuilder()
    sb.append(first.lowercase())
    var i = 1
    while (i < length) {
        sb.append(this[i])
        i += 1
    }
    return sb.toString()
}

/**
 * Returns a copy of this string having its first character replaced with the result of [transform].
 */
@SinceKotlin("1.5")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public fun String.replaceFirstChar(transform: (Char) -> Char): String {
    if (this.length == 0) return this
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
 * Returns a copy of this string having its first character replaced with the result of [transform].
 */
@SinceKotlin("1.5")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public fun String.replaceFirstChar(transform: (Char) -> CharSequence): String {
    if (this.length == 0) return this
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
