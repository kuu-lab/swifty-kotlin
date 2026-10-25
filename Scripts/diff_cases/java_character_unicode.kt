// KUU-2039: Java category values, Byte constants, and UTF-16 widths.
// KOTLINC_FLAGS: -Xjdk-release=17
import java.lang.Character
import java.lang.Character as JavaCharacter

fun count(cp: Int): Int = Character.charCount(cp)
fun space(cp: Int): Boolean = Character.isSpaceChar(cp)
fun category(cp: Int): Int = Character.getType(cp)
fun firstCodeUnit(text: String): Int = text[0].code
fun clear(builder: StringBuilder) { builder.delete(0, builder.length) }
fun byteConstant(value: Byte): Int = value.toInt()

fun main() {
    println(byteConstant(Character.NON_SPACING_MARK))
    println(byteConstant(JavaCharacter.ENCLOSING_MARK))
    println(byteConstant(java.lang.Character.FORMAT))
    val widths = intArrayOf(Int.MIN_VALUE, -1, 0, 0xD800, 0xFFFF, 0x10000, 0x10FFFF, 0x110000, Int.MAX_VALUE)
    for (cp in widths) println(count(cp))
    // One stable representative of every Unicode general category, then boundaries
    // and supplementary marks/letters/private use. Java category 17 is unused.
    val categories = intArrayOf(
        0x0378, 0x41, 0x61, 0x01C5, 0x02B0, 0x4E00, 0x0301, 0x20DD,
        0x0903, 0x30, 0x2160, 0x00B2, 0x20, 0x2028, 0x2029, 0, 0x200D,
        0xE000, 0xD800, 0x2D, 0x28, 0x29, 0x5F, 0x21, 0x2B, 0x24,
        0x5E, 0x1F600, 0x00AB, 0x00BB, 0xDFFF, -1, 0x110000,
        0x10400, 0x10428, 0x1D167, 0xE0001, 0xF0000, 0x10FFFF
    )
    for (cp in categories) println(category(cp))
    val spaces = intArrayOf(0x20, 0xA0, 0x1680, 0x2000, 0x2007, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000,
        0x09, 0x0A, 0x1C, 0x85, 0x200B, 0xFEFF, 0xD800, 0x1F600, -1, 0x110000)
    for (cp in spaces) println(space(cp))
    // xenocom's exact category conversion and constant comparisons.
    for (cp in intArrayOf(0x0301, 0x20DD, 0x200D, 0x41, 0x1D167)) {
        val type = JavaCharacter.getType(cp).toByte()
        println(type == Character.ENCLOSING_MARK || type == Character.NON_SPACING_MARK || type == Character.FORMAT)
    }
    println(firstCodeUnit("A"))
    val builder = StringBuilder("text")
    clear(builder)
    println(builder.length)

    println(Character.isDigit('1'))
    println(Character.isDigit(0x0669))
    println(Character.isLetter('a'))
    println(Character.isLetter(0x10400))
    println(Character.isLetterOrDigit('a'))
    println(Character.isLetterOrDigit('1'))
    println(Character.isLetterOrDigit('_'))
    println(Character.isUpperCase('A'))
    println(Character.isLowerCase('a'))
    println(Character.isTitleCase('ǅ'))
    println(Character.toUpperCase('a'))
    println(Character.toLowerCase('A'))
    println(Character.toUpperCase(97))
    println(Character.toLowerCase(65))
    println(Character.toTitleCase('a'))
    println(Character.toTitleCase(97))
    println(Character.digit('9', 10))
    println(Character.digit(0x0669, 10))
    println(Character.digit('9', 8))
    println(Character.digit('9', 1))
    println(Character.forDigit(9, 10))
    println(Character.forDigit(35, 36))
    println(Character.forDigit(10, 10).code == 0)
    println(Character.getNumericValue('9'))
    println(Character.getNumericValue('A'))
    println(Character.getNumericValue(0x216C))
    println(Character.getNumericValue(0x0F33))
    println(Character.getNumericValue('?'))
    println(Character.isWhitespace(' '))
    println(Character.isWhitespace(0x2000))
    println(Character.isWhitespace(0x2007))
    println(Character.isWhitespace(0x1C))
    println(Character.isSpaceChar(' '))
    println(Character.isISOControl(0x7F))
}
