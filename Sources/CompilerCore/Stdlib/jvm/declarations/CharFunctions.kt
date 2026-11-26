package kotlin.text
@kotlin.internal.InlineOnly
public inline operator fun Char.inc(): Char = (this.code + 1).toChar()
@kotlin.internal.InlineOnly
public inline operator fun Char.dec(): Char = (this.code - 1).toChar()
fun Char.isDigit(): Boolean = false
fun Char.isLowerCase(): Boolean = false
fun Char.isUpperCase(): Boolean = false
fun Char.uppercaseChar(): Char = null!!
fun Char.lowercaseChar(): Char = null!!
fun Char.uppercase(): String = null!!
fun Char.lowercase(): String = null!!
fun Char.titlecase(): String = null!!
fun Char.isWhitespace(): Boolean = false
val Char.directionality: CharDirectionality get() = null!!
fun Char.digitToInt(radix: Int): Int = 0
fun Char.toFloat(): Float = 0f
fun Char.equals(other: Char, ignoreCase: Boolean = null!!): Boolean = null!!
fun checkRadix(radix: Int): Int = 0
