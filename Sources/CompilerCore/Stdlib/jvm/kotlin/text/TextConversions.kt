@file:kotlin.jvm.JvmName("StringsKt")
package kotlin.text

import kotlin.jvm.internal.__jvmEqualsIgnoreCase
import kotlin.jvm.internal.__jvmLowerChar
import kotlin.jvm.internal.__jvmUpperChar

fun CharSequence.asSequence(): kotlin.sequences.Sequence<Char> {
    val source = this
    return object: kotlin.sequences.Sequence<Char> {
        override fun iterator(): Iterator<Char> = object: Iterator<Char> {
            var index = 0
            override fun hasNext(): Boolean = index < source.length
            override fun next(): Char {
                if (!hasNext()) throw NoSuchElementException()
                return source[index++]
            }
        }
    }
}
fun String?.equals(other: String?, ignoreCase: Boolean = false): Boolean {
    if (this == null) return other == null
    if (other == null) return false
    return if (ignoreCase) __jvmEqualsIgnoreCase(this, other) else this == other
}
private fun checkTextRange(start: Int, end: Int, size: Int) {
    if (start < 0 || end > size) throw IndexOutOfBoundsException("startIndex: $start, endIndex: $end, size: $size")
    if (start > end) throw IllegalArgumentException("startIndex ($start) is greater than endIndex ($end).")
}
fun String.toCharArray(startIndex: Int = 0, endIndex: Int = this.length): CharArray {
    checkTextRange(startIndex, endIndex, this.length)
    val result = CharArray(endIndex - startIndex)
    var i = startIndex
    while (i < endIndex) { result[i - startIndex] = this[i]; i++ }
    return result
}
fun CharArray.concatToString(startIndex: Int = 0, endIndex: Int = this.size): String {
    checkTextRange(startIndex, endIndex, this.size)
    val result = StringBuilder()
    var i = startIndex
    while (i < endIndex) { result.append(this[i]); i++ }
    return result.toString()
}
fun CharSequence.split(vararg delimiters: String, ignoreCase: Boolean = false, limit: Int = 0): List<String> = splitStrings(this, delimiters, ignoreCase, limit)
private fun splitStrings(input: CharSequence, delimiters: Array<out String>, ignoreCase: Boolean, limit: Int): List<String> {
    if (limit < 0) throw IllegalArgumentException("Limit must be non-negative, but was $limit")
    val result = mutableListOf<String>()
    var start = 0
    var search = 0
    while (search <= input.length && (limit == 0 || result.size < limit - 1)) {
        var matched = -1
        for (delimiter in delimiters) {
            if (search + delimiter.length <= input.length) {
                var i = 0
                while (i < delimiter.length) {
                    val a = input[search + i]; val b = delimiter[i]
                    if (a != b && (!ignoreCase || __jvmLowerChar(__jvmUpperChar(a)) != __jvmLowerChar(__jvmUpperChar(b)))) break
                    i++
                }
                if (i == delimiter.length) { matched = delimiter.length; break }
            }
        }
        if (matched >= 0) {
            result.add(input.subSequence(start, search).toString())
            start = search + matched
            search = start + if (matched == 0) 1 else 0
        } else search++
    }
    result.add(input.subSequence(start, input.length).toString())
    return result
}
fun CharSequence.split(vararg delimiters: Char, ignoreCase: Boolean = false, limit: Int = 0): List<String> {
    val strings = Array<String>(delimiters.size) { delimiters[it].toString() }
    return splitStrings(this, strings, ignoreCase, limit)
}
private fun indentWidth(line: String): Int {
    var width = 0
    while (width < line.length && line[width].isWhitespace()) width++
    return width
}
fun String.trimIndent(): String {
    val lines = splitStrings(this, arrayOf("\r\n", "\n", "\r"), false, 0)
    var indent = this.length
    for (line in lines) if (!line.isBlank()) {
        val width = indentWidth(line)
        if (width < indent) indent = width
    }
    val result = mutableListOf<String>()
    var i = 0
    for (line in lines) {
        if (!((i == 0 || i == lines.size - 1) && line.isBlank())) result.add(line.drop(if (indent < line.length) indent else line.length))
        i++
    }
    return result.joinToString("\n")
}
fun String.trimMargin(marginPrefix: String = "|"): String {
    if (marginPrefix.isBlank()) throw IllegalArgumentException("marginPrefix must be non-blank string.")
    val lines = splitStrings(this, arrayOf("\r\n", "\n", "\r"), false, 0)
    val result = mutableListOf<String>()
    var i = 0
    for (line in lines) {
        if (!((i == 0 || i == lines.size - 1) && line.isBlank())) {
            val width = indentWidth(line)
            result.add(if (line.startsWith(marginPrefix, width)) line.drop(width + marginPrefix.length) else line)
        }
        i++
    }
    return result.joinToString("\n")
}

fun getLastIndex(value: CharSequence): Int = value.length - 1
fun StringBuilder.clear(): StringBuilder { this.setLength(0); return this }
fun String.toByteOrNull(): Byte? = this.toByteOrNull(10)
fun String.toShortOrNull(): Short? = this.toShortOrNull(10)
fun String.toIntOrNull(): Int? = this.toIntOrNull(10)
fun String.toLongOrNull(): Long? = this.toLongOrNull(10)

fun CharSequence.reversed(): CharSequence = StringBuilder(this).reverse().toString()
fun CharArray.concatToString(): String = this.concatToString(0, this.size)
