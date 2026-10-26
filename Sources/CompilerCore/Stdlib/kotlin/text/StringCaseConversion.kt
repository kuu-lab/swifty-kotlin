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
 * Multi-character mappings such as Latin capital I with dot are preserved, and a
 * capital sigma at the end of a word maps to final sigma.
 */
public fun String.lowercase(): String = this.__kkStringLowercase()

/**
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

@Deprecated("Use lowercase() instead.", ReplaceWith("lowercase()"))
@DeprecatedSinceKotlin(warningSince = "1.5", errorSince = "2.1")
public fun String.toLowerCase(): String = lowercase()

@Deprecated("Use uppercase() instead.", ReplaceWith("uppercase()"))
@DeprecatedSinceKotlin(warningSince = "1.5", errorSince = "2.1")
public fun String.toUpperCase(): String = uppercase()

/**
 * Deprecated by Kotlin, but still provided for compatibility.
 */
@Deprecated(
    "Use replaceFirstChar instead.",
    ReplaceWith("replaceFirstChar { it.titlecase() }")
)
@DeprecatedSinceKotlin(warningSince = "1.5")
public fun String.capitalize(): String {
    if (this.length == 0) return this
    val first = this[0]
    if (!first.isLowerCase()) return this

    val sb = StringBuilder()
    val title = first.titlecaseChar()
    if (title != first.uppercaseChar()) {
        sb.append(title)
    } else {
        sb.append(first.uppercase())
    }
    var i = 1
    while (i < length) {
        sb.append(this[i])
        i += 1
    }
    return sb.toString()
}

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

public fun String.lowercase(locale: java.util.Locale): String =
    this.__kk_lowercase_locale(locale)

public fun String.uppercase(locale: java.util.Locale): String =
    this.__kk_uppercase_locale(locale)
