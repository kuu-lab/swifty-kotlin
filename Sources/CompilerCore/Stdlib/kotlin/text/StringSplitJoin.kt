package kotlin.text

import kotlin.internal.KsSymbolName
import kotlin.sequences.Sequence

// Retained for compatibility with older bundled callers. Current collection
// join APIs live in kotlin.collections and do not route through this bridge.
@KsSymbolName("__kk_string_joinToString")
private external fun <T> List<T>.__kkStringJoinToString(
    separator: String,
    prefix: String,
    postfix: String
): String

// MIGRATION-TEXT-004 / RF-STDLIB-005
// Public split APIs are now source-backed. Runtime fast paths are retained as
// private __kk_* bridges so public kk_string_split* symbols disappear from
// compiler synthetic stubs and member-call lowering.

public fun String.split(delimiter: String): List<String> =
    this.__kk_string_split(delimiter)

public fun String.split(delimiter: String, limit: Int): List<String> =
    this.__kk_string_split_limit(delimiter, false, limit)

public fun String.split(delimiter: String, ignoreCase: Boolean): List<String> =
    this.__kk_string_split_limit(delimiter, ignoreCase, 0)

public fun String.split(delimiter: String, ignoreCase: Boolean, limit: Int): List<String> =
    this.__kk_string_split_limit(delimiter, ignoreCase, limit)

public fun String.splitToSequence(delimiter: String): Sequence<String> =
    this.__kk_string_splitToSequence(delimiter)

// Keep the canonical String vararg surface alongside the existing one-delimiter
// fast paths. A statically String-typed receiver otherwise cannot select the
// CharSequence extension overload when more than one delimiter is supplied.
public fun String.split(
    vararg delimiters: String,
    ignoreCase: Boolean = false,
    limit: Int = 0
): List<String> {
    val delimiterList = mutableListOf<String>()
    for (delimiter in delimiters) delimiterList.add(delimiter)
    return splitByDelimiters(delimiterList, ignoreCase, limit)
}

public fun String.split(
    vararg delimiters: Char,
    ignoreCase: Boolean = false,
    limit: Int = 0
): List<String> {
    val delimiterList = mutableListOf<String>()
    for (delimiter in delimiters) delimiterList.add(delimiter.toString())
    return splitByDelimiters(delimiterList, ignoreCase, limit)
}

public fun String.splitToSequence(
    vararg delimiters: String,
    ignoreCase: Boolean = false,
    limit: Int = 0
): Sequence<String> {
    val delimiterList = mutableListOf<String>()
    for (delimiter in delimiters) delimiterList.add(delimiter)
    return splitByDelimiters(delimiterList, ignoreCase, limit).asSequence()
}

public fun String.splitToSequence(
    vararg delimiters: Char,
    ignoreCase: Boolean = false,
    limit: Int = 0
): Sequence<String> {
    val delimiterList = mutableListOf<String>()
    for (delimiter in delimiters) delimiterList.add(delimiter.toString())
    return splitByDelimiters(delimiterList, ignoreCase, limit).asSequence()
}

// CharSequence split overloads stay source-backed so custom receivers do not
// need to be flattened through a String-only runtime entry point. The scanner
// follows Kotlin's left-to-right delimiter selection: when multiple delimiters
// start at the same position, the first delimiter in the vararg wins.
private fun CharSequence.materializeForSplit(): String {
    if (this is String) return this
    val builder = StringBuilder(length)
    var index = 0
    while (index < length) {
        builder.append(this[index])
        index++
    }
    return builder.toString()
}

private fun CharSequence.splitByDelimiters(
    delimiters: List<String>,
    ignoreCase: Boolean,
    limit: Int
): List<String> {
    require(limit >= 0) { "Limit must be non-negative, but was $limit." }
    val source = materializeForSplit()
    if (limit == 1 || delimiters.isEmpty()) return listOf(source)

    val result = mutableListOf<String>()
    var fieldStart = 0
    var searchStart = 0
    var pieces = 0
    val sourceLength = source.length
    while (searchStart <= sourceLength && (limit == 0 || pieces < limit - 1)) {
        val match = findSplitDelimiter(source, delimiters, searchStart, ignoreCase) ?: break
        val delimiterLength = match.second.length
        result.add(source.substring(fieldStart, match.first))
        pieces++
        if (delimiterLength == 0) {
            // A zero-width delimiter creates a boundary without consuming a
            // character. Keep the field start at the match and advance only
            // the search cursor so the next scan is finite.
            fieldStart = match.first
            searchStart = match.first + 1
        } else {
            fieldStart = match.first + delimiterLength
            searchStart = fieldStart
        }
    }
    result.add(source.substring(fieldStart, sourceLength))
    return result
}

private fun findSplitDelimiter(
    source: String,
    delimiters: List<String>,
    startIndex: Int,
    ignoreCase: Boolean
): Pair<Int, String>? {
    var index = startIndex
    while (index <= source.length) {
        var delimiterIndex = 0
        while (delimiterIndex < delimiters.size) {
            val delimiter = delimiters[delimiterIndex]
            val delimiterLength = delimiter.length
            if (delimiterLength == 0 && index <= source.length) {
                return Pair(index, delimiter)
            }
            if (index + delimiterLength <= source.length) {
                val candidate = source.substring(index, index + delimiterLength)
                if (candidate.equals(delimiter, ignoreCase)) {
                    return Pair(index, delimiter)
                }
            }
            delimiterIndex++
        }
        index++
    }
    return null
}

public fun CharSequence.split(
    vararg delimiters: String,
    ignoreCase: Boolean = false,
    limit: Int = 0
): List<String> {
    val delimiterList = mutableListOf<String>()
    for (delimiter in delimiters) delimiterList.add(delimiter)
    return splitByDelimiters(delimiterList, ignoreCase, limit)
}

public fun CharSequence.split(
    vararg delimiters: Char,
    ignoreCase: Boolean = false,
    limit: Int = 0
): List<String> {
    val delimiterList = mutableListOf<String>()
    for (delimiter in delimiters) delimiterList.add(delimiter.toString())
    return splitByDelimiters(delimiterList, ignoreCase, limit)
}

public fun CharSequence.split(regex: Regex, limit: Int = 0): List<String> =
    regex.split(materializeForSplit(), limit)

public fun CharSequence.splitToSequence(
    vararg delimiters: String,
    ignoreCase: Boolean = false,
    limit: Int = 0
): Sequence<String> {
    val delimiterList = mutableListOf<String>()
    for (delimiter in delimiters) delimiterList.add(delimiter)
    return splitByDelimiters(delimiterList, ignoreCase, limit).asSequence()
}

public fun CharSequence.splitToSequence(
    vararg delimiters: Char,
    ignoreCase: Boolean = false,
    limit: Int = 0
): Sequence<String> {
    val delimiterList = mutableListOf<String>()
    for (delimiter in delimiters) delimiterList.add(delimiter.toString())
    return splitByDelimiters(delimiterList, ignoreCase, limit).asSequence()
}

public fun CharSequence.splitToSequence(regex: Regex, limit: Int = 0): Sequence<String> =
    regex.split(materializeForSplit(), limit).asSequence()
