package kotlin

import kswiftk.internal.*

// MARK: - Basic conversions

val Char.code: Int
    get() = __char_code(this)

fun Char.toInt(): Int = __char_toInt(this)

fun Char.toDouble(): Double = this.code.toDouble()

fun Char.toByte(): Byte = this.code.toByte()

fun Char.toShort(): Short = this.code.toShort()

fun Char.toLong(): Long = this.code.toLong()

fun Char.toFloat(): Float = this.code.toFloat()

// MARK: - Unicode-dependent functions (require runtime)

fun Char.isDigit(): Boolean = __char_isDigit(this)

fun Char.isLetter(): Boolean = __char_isLetter(this)

fun Char.isLetterOrDigit(): Boolean = __char_isLetterOrDigit(this)

fun Char.isUpperCase(): Boolean = __char_isUpperCase(this)

fun Char.isLowerCase(): Boolean = __char_isLowerCase(this)

fun Char.isWhitespace(): Boolean = __char_isWhitespace(this)

fun Char.isDefined(): Boolean = __char_isDefined(this)

fun Char.isSurrogate(): Boolean = __char_isSurrogate(this)

fun Char.isHighSurrogate(): Boolean = __char_isHighSurrogate(this)

fun Char.isLowSurrogate(): Boolean = __char_isLowSurrogate(this)

fun Char.isISOControl(): Boolean = __char_isISOControl(this)

fun Char.isTitleCase(): Boolean = __char_isTitleCase(this)

fun Char.isJavaIdentifierPart(): Boolean = __char_isJavaIdentifierPart(this)

fun Char.isIdentifierIgnorable(): Boolean = __char_isIdentifierIgnorable(this)

fun Char.isUnicodeIdentifierPart(): Boolean = __char_isUnicodeIdentifierPart(this)

fun Char.isJavaIdentifierStart(): Boolean = __char_isJavaIdentifierStart(this)

// MARK: - Case conversion (require runtime)

fun Char.uppercase(): Char = __char_uppercaseChar(this)

fun Char.lowercase(): Char = __char_lowercaseChar(this)

fun Char.titlecase(): Char = __char_titlecaseChar(this)

fun Char.uppercaseChar(): Char = __char_uppercaseChar(this)

fun Char.lowercaseChar(): Char = __char_lowercaseChar(this)

fun Char.titlecaseChar(): Char = __char_titlecaseChar(this)

// MARK: - Numeric conversions (require runtime)

fun Char.digitToInt(): Int = __char_digitToInt(this)

fun Char.digitToIntOrNull(): Int? = __char_digitToIntOrNull(this)

fun Char.digitToInt(radix: Int): Int = __char_digitToInt_radix(this, radix)

// MARK: - Comparison

operator fun Char.minus(other: Int): Char = (this.code - other).toChar()
