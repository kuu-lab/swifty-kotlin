/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib common text declarations.
 */

package kotlin.text

@Deprecated("Use CharArray.concatToString() instead", ReplaceWith("chars.concatToString()"))
@DeprecatedSinceKotlin(warningSince = "1.4", errorSince = "1.5")
public fun String(chars: CharArray): String =
    StringBuilder().append(chars).toString()

/**
 * @throws IndexOutOfBoundsException if either [offset] or [length] are less than zero
 * or `offset + length` is out of [chars] array bounds.
 */
@Deprecated("Use CharArray.concatToString(startIndex, endIndex) instead", ReplaceWith("chars.concatToString(offset, offset + length)"))
@DeprecatedSinceKotlin(warningSince = "1.4", errorSince = "1.5")
public fun String(chars: CharArray, offset: Int, length: Int): String =
    StringBuilder().append(chars, offset, length).toString()

public fun <T : Appendable> T.append(vararg value: CharSequence?): T {
    var index = 0
    while (index < value.size) {
        this.append(value[index])
        index++
    }
    return this
}

public fun <T : Appendable> T.appendRange(value: CharSequence, startIndex: Int, endIndex: Int): T {
    this.append(value, startIndex, endIndex)
    return this
}

public inline fun HexFormat(builderAction: HexFormat.Builder.() -> Unit): HexFormat =
    HexFormat.Builder().apply(builderAction).build()

@PublishedApi
internal fun checkRadix(radix: Int): Int {
    if (radix < Char.MIN_RADIX || radix > Char.MAX_RADIX) {
        throw IllegalArgumentException("radix $radix was not in valid range ${Char.MIN_RADIX}..${Char.MAX_RADIX}")
    }
    return radix
}

private const val RADIX_DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

// Digits are produced in negative space (n stays <= 0 throughout) so
// Int.MIN_VALUE / Long.MIN_VALUE never need to be negated.
@PublishedApi
internal fun intToString(value: Int, radix: Int): String {
    checkRadix(radix)
    if (value == 0) return "0"
    val negative = value < 0
    var n = if (value > 0) -value else value
    var result = ""
    while (n != 0) {
        val digit = -(n % radix)
        result = RADIX_DIGITS[digit].toString() + result
        n /= radix
    }
    return if (negative) "-" + result else result
}

@PublishedApi
internal fun longToString(value: Long, radix: Int): String {
    checkRadix(radix)
    if (value == 0L) return "0"
    val negative = value < 0L
    var n = if (value > 0L) -value else value
    val radixLong = radix.toLong()
    var result = ""
    while (n != 0L) {
        val digit = -(n % radixLong)
        result = RADIX_DIGITS[digit.toInt()].toString() + result
        n /= radixLong
    }
    return if (negative) "-" + result else result
}
