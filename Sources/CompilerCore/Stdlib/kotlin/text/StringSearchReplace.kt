package kotlin.text

import kswiftk.internal.*
import kotlin.internal.KsSymbolName

// String search and replace functions migrated from Swift Runtime
// MIGRATION-TEXT-002

public fun String.replace(oldValue: String, newValue: String, ignoreCase: Boolean = false): String {
    // Use the runtime string-to-list bridge for character traversal. The flat
    // String aggregate stores UTF-8 byte length, while Kotlin indexing is
    // character-based; using `length`/`this[i]` here can walk past non-ASCII
    // input and raise StringIndexOutOfBoundsException.
    val sourceChars = toList()
    val oldLength = oldValue.toList().size
    val sourceLength = sourceChars.size
    if (oldLength == 0) {
        val sb = StringBuilder()
        sb.append(newValue)
        var i = 0
        while (i < sourceLength) {
            sb.append(sourceChars[i])
            sb.append(newValue)
            i++
        }
        return sb.toString()
    }
    val sb = StringBuilder()
    var start = 0
    while (true) {
        val idx = indexOf(oldValue, start, ignoreCase)
        if (idx == -1) {
            __kk_appendStringRange(sb, sourceChars, start, sourceLength)
            break
        }
        __kk_appendStringRange(sb, sourceChars, start, idx)
        sb.append(newValue)
        start = idx + oldLength
    }
    return sb.toString()
}

public fun String.replace(oldChar: Char, newChar: Char, ignoreCase: Boolean = false): String {
    val sb = StringBuilder()
    var i = 0
    while (i < length) {
        val c = this[i]
        if (__kkCharsEqual(c, oldChar, ignoreCase)) {
            sb.append(newChar)
        } else {
            sb.append(c)
        }
        i++
    }
    return sb.toString()
}

public fun String.replace(regex: Regex, replacement: String): String =
    regex.replace(this, replacement)

public fun String.replaceFirst(oldValue: String, newValue: String, ignoreCase: Boolean = false): String {
    val sourceChars = toList()
    val oldLength = oldValue.toList().size
    val sourceLength = sourceChars.size
    val idx = indexOf(oldValue, 0, ignoreCase)
    if (idx == -1) return this
    val sb = StringBuilder()
    __kk_appendStringRange(sb, sourceChars, 0, idx)
    sb.append(newValue)
    __kk_appendStringRange(sb, sourceChars, idx + oldLength, sourceLength)
    return sb.toString()
}

public fun String.replaceFirst(oldChar: Char, newChar: Char, ignoreCase: Boolean = false): String {
    val sb = StringBuilder()
    var replaced = false
    var i = 0
    while (i < length) {
        val c = this[i]
        if (!replaced && (c == oldChar || (ignoreCase && c.lowercaseChar() == oldChar.lowercaseChar()))) {
            sb.append(newChar)
            replaced = true
        } else {
            sb.append(c)
        }
        i++
    }
    if (!replaced) return this
    return sb.toString()
}

public fun String.replaceFirst(regex: Regex, replacement: String): String =
    regex.replaceFirst(this, replacement)

public fun String.split(regex: Regex): List<String> =
    regex.split(this, 0)

public fun String.split(regex: Regex, limit: Int): List<String> =
    regex.split(this, limit)

public infix fun String.matches(regex: Regex): Boolean =
    __kk_string_matches_regex(regex)

@kotlin.internal.InlineOnly
public inline infix fun CharSequence.matches(regex: Regex): Boolean {
    // Regex currently accepts String input. Preserve indexed CharSequence
    // semantics instead of trusting a custom implementation's toString().
    if (this is String) return regex.matches(this)
    if (this is StringBuilder) return regex.matches(this.toString())
    val builder = StringBuilder()
    var i = 0
    val size = length
    while (i < size) {
        builder.append(this[i])
        i++
    }
    return regex.matches(builder.toString())
}

public operator fun String.contains(regex: Regex): Boolean =
    __kk_string_contains_regex(regex)

public operator fun CharSequence.contains(regex: Regex): Boolean =
    regex.containsMatchIn(charSequenceRegexInput(this))

private fun charSequenceRegexInput(value: CharSequence): String {
    if (value is String) return value.toString()
    val length = value.length
    val result = StringBuilder(length)
    var index = 0
    while (index < length) {
        result.append(value[index])
        index++
    }
    return result.toString()
}

public fun String.toRegex(): Regex =
    __kk_string_toRegex()

public fun String.toRegex(option: RegexOption): Regex =
    __kk_string_toRegex_with_option(option)

public fun String.toRegex(options: Set<RegexOption>): Regex =
    __kk_string_toRegex_with_options(options)

public fun String.substringBefore(delimiter: String, missingDelimiterValue: String = this): String {
    val index = indexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(0, index)
}

public fun String.substringBefore(delimiter: Char, missingDelimiterValue: String = this): String {
    val index = indexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(0, index)
}

public fun String.substringAfter(delimiter: String, missingDelimiterValue: String = this): String {
    val index = indexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(index + delimiter.length)
}

public fun String.substringAfter(delimiter: Char, missingDelimiterValue: String = this): String {
    val index = indexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(index + 1)
}

public fun String.substringBeforeLast(delimiter: String, missingDelimiterValue: String = this): String {
    val index = lastIndexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(0, index)
}

public fun String.substringBeforeLast(delimiter: Char, missingDelimiterValue: String = this): String {
    val index = lastIndexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(0, index)
}

public fun String.substringAfterLast(delimiter: String, missingDelimiterValue: String = this): String {
    val index = lastIndexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(index + delimiter.length)
}

public fun String.substringAfterLast(delimiter: Char, missingDelimiterValue: String = this): String {
    val index = lastIndexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(index + 1)
}

public fun String.replaceBefore(delimiter: String, replacement: String, missingDelimiterValue: String = this): String {
    val index = indexOf(delimiter)
    return if (index == -1) missingDelimiterValue else replacement + substring(index)
}

public fun String.replaceBefore(delimiter: Char, replacement: String, missingDelimiterValue: String = this): String {
    val index = indexOf(delimiter)
    return if (index == -1) missingDelimiterValue else replacement + substring(index)
}

public fun String.replaceAfter(delimiter: String, replacement: String, missingDelimiterValue: String = this): String {
    val index = indexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(0, index + delimiter.length) + replacement
}

public fun String.replaceAfter(delimiter: Char, replacement: String, missingDelimiterValue: String = this): String {
    val index = indexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(0, index + 1) + replacement
}

public fun String.replaceAfterLast(delimiter: String, replacement: String, missingDelimiterValue: String = this): String {
    val index = lastIndexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(0, index + delimiter.length) + replacement
}

public fun String.replaceAfterLast(delimiter: Char, replacement: String, missingDelimiterValue: String = this): String {
    val index = lastIndexOf(delimiter)
    return if (index == -1) missingDelimiterValue else substring(0, index + 1) + replacement
}

public fun String.replaceBeforeLast(delimiter: String, replacement: String, missingDelimiterValue: String = this): String {
    val index = lastIndexOf(delimiter)
    return if (index == -1) missingDelimiterValue else replacement + substring(index)
}

public fun String.replaceBeforeLast(delimiter: Char, replacement: String, missingDelimiterValue: String = this): String {
    val index = lastIndexOf(delimiter)
    return if (index == -1) missingDelimiterValue else replacement + substring(index)
}

@KsSymbolName("__kk_string_matches_regex_flat")
private external fun String.__kk_string_matches_regex(regex: Regex): Boolean

@KsSymbolName("__kk_string_contains_regex_flat")
private external fun String.__kk_string_contains_regex(regex: Regex): Boolean

@KsSymbolName("__kk_string_toRegex_flat")
private external fun String.__kk_string_toRegex(): Regex

@KsSymbolName("__kk_string_toRegex_with_option_flat")
private external fun String.__kk_string_toRegex_with_option(option: RegexOption): Regex

@KsSymbolName("__kk_string_toRegex_with_options_flat")
private external fun String.__kk_string_toRegex_with_options(options: Set<RegexOption>): Regex

private fun __kk_appendStringRange(sb: StringBuilder, value: List<Char>, startIndex: Int, endIndex: Int) {
    var i = startIndex
    while (i < endIndex) {
        sb.append(value[i])
        i++
    }
}
