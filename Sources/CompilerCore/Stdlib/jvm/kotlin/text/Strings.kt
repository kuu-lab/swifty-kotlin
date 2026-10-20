package kotlin.text

import kotlin.jvm.internal.__jvmParseByte
import kotlin.jvm.internal.__jvmParseShort
import kotlin.jvm.internal.__jvmParseInt
import kotlin.jvm.internal.__jvmParseLong
import kotlin.jvm.internal.__jvmParseFloat
import kotlin.jvm.internal.__jvmParseDouble
import kotlin.jvm.internal.__jvmSubstring
import kotlin.jvm.internal.__jvmRootLocale
import kotlin.jvm.internal.__jvmUppercase
import kotlin.jvm.internal.__jvmLowercase
import kotlin.jvm.internal.__jvmIndexOf
import kotlin.jvm.internal.__jvmLastIndexOf
import kotlin.jvm.internal.__jvmUpperChar
import kotlin.jvm.internal.__jvmLowerChar
import kotlin.jvm.internal.__jvmEqualsIgnoreCase

public fun String.isEmpty(): Boolean = this.length == 0
public fun String.isNotEmpty(): Boolean = this.length != 0
public fun CharSequence.isEmpty(): Boolean = this.length == 0
public fun CharSequence.isNotEmpty(): Boolean = this.length != 0
public fun CharSequence.isBlank(): Boolean {
    var index = 0
    while (index < this.length) {
        if (!this[index].isWhitespace()) return false
        index++
    }
    return true
}
public fun CharSequence.isNotBlank(): Boolean = !this.isBlank()
public fun String?.orEmpty(): String = if (this == null) "" else this
public fun String?.isNullOrEmpty(): Boolean = this == null || this.length == 0
public fun String?.isNullOrBlank(): Boolean = this == null || this.isBlank()
public fun CharSequence.first(): Char {
    if (this.length == 0) throw NoSuchElementException("Char sequence is empty.")
    return this[0]
}
public fun CharSequence.last(): Char {
    if (this.length == 0) throw NoSuchElementException("Char sequence is empty.")
    return this[this.length - 1]
}
public fun CharSequence.firstOrNull(): Char? = if (this.length == 0) null else this[0]
public fun CharSequence.lastOrNull(): Char? = if (this.length == 0) null else this[this.length - 1]

private fun checkCount(n: Int) {
    if (n < 0) throw IllegalArgumentException("Requested character count $n is less than zero.")
}
public fun String.take(n: Int): String {
    checkCount(n)
    return __jvmSubstring(this, 0, if (n < this.length) n else this.length)
}
public fun String.takeLast(n: Int): String {
    checkCount(n)
    return __jvmSubstring(this, if (n < this.length) this.length - n else 0, this.length)
}
public fun String.drop(n: Int): String {
    checkCount(n)
    return __jvmSubstring(this, if (n < this.length) n else this.length, this.length)
}
public fun String.dropLast(n: Int): String {
    checkCount(n)
    return __jvmSubstring(this, 0, if (n < this.length) this.length - n else 0)
}
public fun String.padStart(length: Int, padChar: Char = ' '): String {
    if (length < 0) throw IllegalArgumentException("Desired length $length is less than zero.")
    if (length <= this.length) return this
    val result = StringBuilder()
    var n = this.length
    while (n < length) { result.append(padChar); n++ }
    result.append(this)
    return result.toString()
}
public fun String.padEnd(length: Int, padChar: Char = ' '): String {
    if (length < 0) throw IllegalArgumentException("Desired length $length is less than zero.")
    if (length <= this.length) return this
    val result = StringBuilder(this)
    var n = this.length
    while (n < length) { result.append(padChar); n++ }
    return result.toString()
}
public fun CharSequence.repeat(n: Int): String {
    if (n < 0) throw IllegalArgumentException("Count 'n' must be non-negative, but was $n.")
    val result = StringBuilder()
    var index = 0
    while (index < n) { result.append(this); index++ }
    return result.toString()
}
public fun String.uppercase(): String = __jvmUppercase(this, __jvmRootLocale())
public fun String.lowercase(): String = __jvmLowercase(this, __jvmRootLocale())
public fun String.reversed(): String {
    val builder = StringBuilder(this)
    return builder.reverse().toString()
}
public fun String?.toBoolean(): Boolean = this != null && __jvmEqualsIgnoreCase(this, "true")
public fun String.toBooleanStrict(): Boolean {
    if (this == "true") return true
    if (this == "false") return false
    throw IllegalArgumentException("The string doesn't represent a boolean value: $this")
}
public fun String.toBooleanStrictOrNull(): Boolean? = if (this == "true") true else if (this == "false") false else null

public fun String.toByte(radix: Int = 10): Byte = __jvmParseByte(this, checkRadix(radix))
public fun String.toByteOrNull(radix: Int = 10): Byte? {
    checkRadix(radix)
    try { return __jvmParseByte(this, checkRadix(radix)) } catch (error: NumberFormatException) { return null }
}

public fun String.toShort(radix: Int = 10): Short = __jvmParseShort(this, checkRadix(radix))
public fun String.toShortOrNull(radix: Int = 10): Short? {
    checkRadix(radix)
    try { return __jvmParseShort(this, checkRadix(radix)) } catch (error: NumberFormatException) { return null }
}

public fun String.toInt(radix: Int = 10): Int = __jvmParseInt(this, checkRadix(radix))
public fun String.toIntOrNull(radix: Int = 10): Int? {
    checkRadix(radix)
    try { return __jvmParseInt(this, checkRadix(radix)) } catch (error: NumberFormatException) { return null }
}

public fun String.toLong(radix: Int = 10): Long = __jvmParseLong(this, checkRadix(radix))
public fun String.toLongOrNull(radix: Int = 10): Long? {
    checkRadix(radix)
    try { return __jvmParseLong(this, checkRadix(radix)) } catch (error: NumberFormatException) { return null }
}

public fun String.toFloat(): Float = __jvmParseFloat(this)
public fun String.toFloatOrNull(): Float? {
    try { return __jvmParseFloat(this) } catch (error: NumberFormatException) { return null }
}

public fun String.toDouble(): Double = __jvmParseDouble(this)
public fun String.toDoubleOrNull(): Double? {
    try { return __jvmParseDouble(this) } catch (error: NumberFormatException) { return null }
}


private fun charsEqual(a: Char, b: Char, ignoreCase: Boolean): Boolean {
    if (a == b) return true
    if (!ignoreCase) return false
    val upperA = __jvmUpperChar(a)
    val upperB = __jvmUpperChar(b)
    return upperA == upperB || __jvmLowerChar(upperA) == __jvmLowerChar(upperB)
}
private fun regionMatches(value: CharSequence, offset: Int, other: CharSequence, ignoreCase: Boolean): Boolean {
    if (offset < 0 || offset > value.length - other.length) return false
    var i = 0
    while (i < other.length) {
        if (!charsEqual(value[offset + i], other[i], ignoreCase)) return false
        i++
    }
    return true
}
public fun String.startsWith(prefix: String, ignoreCase: Boolean = false): Boolean = regionMatches(this, 0, prefix, ignoreCase)
public fun String.startsWith(prefix: String, startIndex: Int, ignoreCase: Boolean = false): Boolean = regionMatches(this, startIndex, prefix, ignoreCase)
public fun String.endsWith(suffix: String, ignoreCase: Boolean = false): Boolean = regionMatches(this, this.length - suffix.length, suffix, ignoreCase)
public fun CharSequence.startsWith(char: Char, ignoreCase: Boolean = false): Boolean = this.length > 0 && charsEqual(this[0], char, ignoreCase)
public fun CharSequence.endsWith(char: Char, ignoreCase: Boolean = false): Boolean = this.length > 0 && charsEqual(this[this.length - 1], char, ignoreCase)

public fun CharSequence.indexOf(string: String, startIndex: Int = 0, ignoreCase: Boolean = false): Int {
    if (!ignoreCase && this is String) return __jvmIndexOf(this, string, startIndex)
    var i = if (startIndex < 0) 0 else startIndex
    val end = this.length - string.length
    while (i <= end) {
        if (regionMatches(this, i, string, ignoreCase)) return i
        i++
    }
    return -1
}
public fun CharSequence.indexOf(char: Char, startIndex: Int = 0, ignoreCase: Boolean = false): Int {
    var i = if (startIndex < 0) 0 else startIndex
    while (i < this.length) {
        if (charsEqual(this[i], char, ignoreCase)) return i
        i++
    }
    return -1
}
public fun CharSequence.lastIndexOf(string: String, startIndex: Int = this.length - 1, ignoreCase: Boolean = false): Int {
    if (!ignoreCase && this is String) return __jvmLastIndexOf(this, string, startIndex)
    var i = if (startIndex < this.length) startIndex else this.length - 1
    while (i >= 0) {
        if (regionMatches(this, i, string, ignoreCase)) return i
        i--
    }
    return -1
}
public fun CharSequence.lastIndexOf(char: Char, startIndex: Int = this.length - 1, ignoreCase: Boolean = false): Int {
    var i = if (startIndex < this.length) startIndex else this.length - 1
    while (i >= 0) {
        if (charsEqual(this[i], char, ignoreCase)) return i
        i--
    }
    return -1
}
public operator fun CharSequence.contains(other: CharSequence, ignoreCase: Boolean = false): Boolean {
    var index = 0
    val end = this.length - other.length
    while (index <= end) {
        if (regionMatches(this, index, other, ignoreCase)) return true
        index++
    }
    return false
}
public operator fun CharSequence.contains(char: Char, ignoreCase: Boolean = false): Boolean = this.indexOf(char, 0, ignoreCase) >= 0
public fun String.removePrefix(prefix: CharSequence): String = if (regionMatches(this, 0, prefix, false)) __jvmSubstring(this, prefix.length, this.length) else this
public fun String.removeSuffix(suffix: CharSequence): String = if (regionMatches(this, this.length - suffix.length, suffix, false)) __jvmSubstring(this, 0, this.length - suffix.length) else this
public fun String.removeSurrounding(prefix: CharSequence, suffix: CharSequence): String {
    if (this.length >= prefix.length + suffix.length && regionMatches(this, 0, prefix, false) && regionMatches(this, this.length - suffix.length, suffix, false)) return __jvmSubstring(this, prefix.length, this.length - suffix.length)
    return this
}
public fun String.removeSurrounding(delimiter: CharSequence): String = this.removeSurrounding(delimiter, delimiter)

public fun CharSequence.trim(): CharSequence {
    var start = 0
    var end = this.length
    while (start < end && this[start].isWhitespace()) start++
    while (end > start && this[end - 1].isWhitespace()) end--
    return this.subSequence(start, end)
}
public fun CharSequence.trimStart(): CharSequence {
    var start = 0
    while (start < this.length && this[start].isWhitespace()) start++
    return this.subSequence(start, this.length)
}
public fun CharSequence.trimEnd(): CharSequence {
    var end = this.length
    while (end > 0 && this[end - 1].isWhitespace()) end--
    return this.subSequence(0, end)
}
private fun containsChar(chars: CharArray, char: Char): Boolean {
    for (candidate in chars) if (candidate == char) return true
    return false
}
public fun String.trim(vararg chars: Char): String {
    var start = 0
    var end = this.length
    while (start < end && containsChar(chars, this[start])) start++
    while (end > start && containsChar(chars, this[end - 1])) end--
    return __jvmSubstring(this, start, end)
}
public fun String.trimStart(vararg chars: Char): String {
    var start = 0
    while (start < this.length && containsChar(chars, this[start])) start++
    return __jvmSubstring(this, start, this.length)
}
public fun String.trimEnd(vararg chars: Char): String {
    var end = this.length
    while (end > 0 && containsChar(chars, this[end - 1])) end--
    return __jvmSubstring(this, 0, end)
}

public fun String.substringBefore(delimiter: String, missingDelimiterValue: String = this): String {
    val index = this.indexOf(delimiter)
    return if (index < 0) missingDelimiterValue else __jvmSubstring(this, 0, index)
}

public fun String.substringBefore(delimiter: Char, missingDelimiterValue: String = this): String {
    val index = this.indexOf(delimiter)
    return if (index < 0) missingDelimiterValue else __jvmSubstring(this, 0, index)
}

public fun String.substringAfter(delimiter: String, missingDelimiterValue: String = this): String {
    val index = this.indexOf(delimiter)
    return if (index < 0) missingDelimiterValue else __jvmSubstring(this, index + delimiter.length, this.length)
}

public fun String.substringAfter(delimiter: Char, missingDelimiterValue: String = this): String {
    val index = this.indexOf(delimiter)
    return if (index < 0) missingDelimiterValue else __jvmSubstring(this, index + 1, this.length)
}

public fun String.substringBeforeLast(delimiter: String, missingDelimiterValue: String = this): String {
    val index = this.lastIndexOf(delimiter)
    return if (index < 0) missingDelimiterValue else __jvmSubstring(this, 0, index)
}

public fun String.substringBeforeLast(delimiter: Char, missingDelimiterValue: String = this): String {
    val index = this.lastIndexOf(delimiter)
    return if (index < 0) missingDelimiterValue else __jvmSubstring(this, 0, index)
}

public fun String.substringAfterLast(delimiter: String, missingDelimiterValue: String = this): String {
    val index = this.lastIndexOf(delimiter)
    return if (index < 0) missingDelimiterValue else __jvmSubstring(this, index + delimiter.length, this.length)
}

public fun String.substringAfterLast(delimiter: Char, missingDelimiterValue: String = this): String {
    val index = this.lastIndexOf(delimiter)
    return if (index < 0) missingDelimiterValue else __jvmSubstring(this, index + 1, this.length)
}

public fun String.replace(oldValue: String, newValue: String, ignoreCase: Boolean = false): String {
    var found = this.indexOf(oldValue, 0, ignoreCase)
    if (found < 0) return this
    val result = StringBuilder()
    var start = 0
    val advance = if (oldValue.length == 0) 1 else oldValue.length
    while (found >= 0) {
        result.append(__jvmSubstring(this, start, found)); result.append(newValue)
        start = found + oldValue.length
        if (found > this.length - advance) break
        found = this.indexOf(oldValue, found + advance, ignoreCase)
    }
    result.append(__jvmSubstring(this, start, this.length))
    return result.toString()
}
public fun String.replaceFirst(oldValue: String, newValue: String, ignoreCase: Boolean = false): String {
    val found = this.indexOf(oldValue, 0, ignoreCase)
    if (found < 0) return this
    return __jvmSubstring(this, 0, found) + newValue + __jvmSubstring(this, found + oldValue.length, this.length)
}
public fun String.replace(oldChar: Char, newChar: Char, ignoreCase: Boolean = false): String {
    val result = StringBuilder()
    var index = 0
    while (index < this.length) {
        val char = this[index]
        result.append(if (charsEqual(char, oldChar, ignoreCase)) newChar else char)
        index++
    }
    return result.toString()
}
public fun String.replaceFirst(oldChar: Char, newChar: Char, ignoreCase: Boolean = false): String {
    val found = this.indexOf(oldChar, 0, ignoreCase)
    if (found < 0) return this
    return __jvmSubstring(this, 0, found) + newChar + __jvmSubstring(this, found + 1, this.length)
}
public fun String.compareTo(other: String, ignoreCase: Boolean = false): Int {
    val limit = if (this.length < other.length) this.length else other.length
    var index = 0
    while (index < limit) {
        var a = this[index]
        var b = other[index]
        if (a != b) {
            if (ignoreCase) {
                a = __jvmLowerChar(__jvmUpperChar(a))
                b = __jvmLowerChar(__jvmUpperChar(b))
            }
            if (a != b) return a.code - b.code
        }
        index++
    }
    return this.length - other.length
}

public fun String.trim(): String = (this as CharSequence).trim().toString()
public fun String.trimStart(): String = (this as CharSequence).trimStart().toString()
public fun String.trimEnd(): String = (this as CharSequence).trimEnd().toString()
