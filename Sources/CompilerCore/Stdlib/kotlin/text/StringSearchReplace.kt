package kotlin.text

import kswiftk.internal.*
import kotlin.internal.KsSymbolName

// String search and replace functions migrated from Swift Runtime
// MIGRATION-TEXT-002

/**
 * Returns a new string obtained by replacing all occurrences of the [oldValue] substring
 * in this string with the specified [newValue] string.
 *
 * @param oldValue The substring to be replaced.
 * @param newValue The replacement string.
 * @param ignoreCase `true` to ignore character case when matching [oldValue]. Default is `false`.
 */
public fun String.replace(oldValue: String, newValue: String, ignoreCase: Boolean = false): String {
    // Use the runtime string-to-list bridge for character traversal. The flat
    // String aggregate stores UTF-8 byte length, while Kotlin indexing is
    // character-based; using `length`/`this[i]` here can walk past non-ASCII
    // input and raise StringIndexOutOfBoundsException.
    val sourceChars = this.toList()
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
        val idx = this.indexOf(oldValue, start, ignoreCase)
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

/**
 * Returns a new string obtained by replacing all occurrences of the [oldChar] character
 * in this string with the [newChar] character.
 *
 * @param oldChar The character to replace.
 * @param newChar The replacement character.
 * @param ignoreCase `true` to ignore character case. Default is `false`.
 */
public fun String.replace(oldChar: Char, newChar: Char, ignoreCase: Boolean = false): String {
    val sb = StringBuilder()
    var i = 0
    while (i < length) {
        val c = this[i]
        if (c == oldChar || (ignoreCase && c.lowercaseChar() == oldChar.lowercaseChar())) {
            sb.append(newChar)
        } else {
            sb.append(c)
        }
        i++
    }
    return sb.toString()
}

/**
 * Returns a new string obtained by replacing each occurrence of [regex]
 * with the specified [replacement] string.
 */
public fun String.replace(regex: Regex, replacement: String): String =
    this.__kk_replace_regex(regex, replacement)

/**
 * Returns a new string with the first occurrence of [oldValue] replaced with [newValue].
 *
 * @param oldValue The substring to replace the first occurrence of.
 * @param newValue The replacement string.
 * @param ignoreCase `true` to ignore character case when finding [oldValue]. Default is `false`.
 */
public fun String.replaceFirst(oldValue: String, newValue: String, ignoreCase: Boolean = false): String {
    val sourceChars = this.toList()
    val oldLength = oldValue.toList().size
    val sourceLength = sourceChars.size
    val idx = this.indexOf(oldValue, 0, ignoreCase)
    if (idx == -1) return this
    val sb = StringBuilder()
    __kk_appendStringRange(sb, sourceChars, 0, idx)
    sb.append(newValue)
    __kk_appendStringRange(sb, sourceChars, idx + oldLength, sourceLength)
    return sb.toString()
}

/**
 * Returns a new string with the first occurrence of [oldChar] replaced with [newChar].
 *
 * @param oldChar The character to replace.
 * @param newChar The replacement character.
 * @param ignoreCase `true` to ignore character case. Default is `false`.
 */
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

/**
 * Returns a new string with the first occurrence of [regex] replaced by [replacement].
 */
public fun String.replaceFirst(regex: Regex, replacement: String): String =
    this.__kk_replaceFirst_regex(regex, replacement)

/**
 * Splits this string around matches of [regex].
 */
public fun String.split(regex: Regex): List<String> =
    this.__kk_split_regex(regex)

@KsSymbolName("kk_string_replace_regex")
private external fun String.__kk_replace_regex(regex: Regex, replacement: String): String

@KsSymbolName("kk_string_replaceFirst_regex")
private external fun String.__kk_replaceFirst_regex(regex: Regex, replacement: String): String

@KsSymbolName("kk_string_split_regex_flat")
private external fun String.__kk_split_regex(regex: Regex): List<String>

private fun __kk_appendStringRange(sb: StringBuilder, value: List<Char>, startIndex: Int, endIndex: Int) {
    var i = startIndex
    while (i < endIndex) {
        sb.append(value[i])
        i++
    }
}
