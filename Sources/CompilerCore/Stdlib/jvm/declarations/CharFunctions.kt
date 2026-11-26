package kotlin.text
@kotlin.internal.InlineOnly
public inline operator fun Char.inc(): Char = (this.code + 1).toChar()
@kotlin.internal.InlineOnly
public inline operator fun Char.dec(): Char = (this.code - 1).toChar()
@kotlin.internal.InlineOnly
public inline fun Char.isHighSurrogate(): Boolean = java.lang.Character.isHighSurrogate(this)
@kotlin.internal.InlineOnly
public inline fun Char.isLowSurrogate(): Boolean = java.lang.Character.isLowSurrogate(this)
@kotlin.internal.InlineOnly
public inline fun Char.isDigit(): Boolean = java.lang.Character.isDigit(this)
@kotlin.internal.InlineOnly
public inline fun Char.isLowerCase(): Boolean = java.lang.Character.isLowerCase(this)
@kotlin.internal.InlineOnly
public inline fun Char.isUpperCase(): Boolean = java.lang.Character.isUpperCase(this)
@kotlin.internal.InlineOnly
public inline fun Char.uppercaseChar(): Char = java.lang.Character.toUpperCase(this)
@kotlin.internal.InlineOnly
public inline fun Char.lowercaseChar(): Char = java.lang.Character.toLowerCase(this)
@kotlin.internal.InlineOnly
public inline fun Char.uppercase(): String = this.toString().uppercase()
@kotlin.internal.InlineOnly
public inline fun Char.lowercase(): String = this.toString().lowercase()
fun Char.titlecase(): String = null!!
fun Char.isWhitespace(): Boolean = false
val Char.directionality: CharDirectionality get() = null!!
fun Char.digitToInt(radix: Int): Int = 0
@kotlin.internal.InlineOnly
public inline fun Char.toFloat(): Float = this.code.toFloat()
fun Char.equals(other: Char, ignoreCase: Boolean = null!!): Boolean = null!!
fun checkRadix(radix: Int): Int = 0
