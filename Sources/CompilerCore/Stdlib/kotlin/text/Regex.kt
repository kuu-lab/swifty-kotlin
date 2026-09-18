package kotlin.text

import kotlin.internal.KsSymbolName

// KSP-487
// Regex public API layer migrated from synthetic Swift stubs.
// RegexOption, Regex constructors, members, and companion object live here;
// engine entry points are demoted to the __kk_* runtime bridges.

public enum class RegexOption {
    IGNORE_CASE,
    MULTILINE,
    LITERAL,
    UNIX_LINES,
    COMMENTS,
    DOT_MATCHES_ALL,
    CANON_EQ
}

public class Regex {
    @KsSymbolName("__kk_regex_create_flat")
    public constructor(pattern: String)

    @KsSymbolName("__kk_regex_create_with_option_flat")
    public constructor(pattern: String, option: RegexOption)

    @KsSymbolName("__kk_regex_create_with_options_flat")
    public constructor(pattern: String, options: Set<RegexOption>)

    public companion object {
        @KsSymbolName("__kk_regex_from_literal_flat")
        public external fun fromLiteral(literal: String): Regex
    }

    @KsSymbolName("__kk_regex_find_flat")
    public external fun find(input: String): MatchResult?

    public fun find(input: CharSequence, startIndex: Int = 0): MatchResult? {
        val source = input.regexInputString()
        require(startIndex >= 0 && startIndex <= source.length) {
            "Start index out of bounds: $startIndex"
        }
        return findFrom(source, startIndex)
    }

    @KsSymbolName("__kk_regex_findAll_flat")
    public external fun findAll(input: String): List<MatchResult>

    public fun findAll(input: CharSequence, startIndex: Int = 0): Sequence<MatchResult> {
        val source = input.regexInputString()
        require(startIndex >= 0 && startIndex <= source.length) {
            "Start index out of bounds: $startIndex"
        }
        val result = ArrayList<MatchResult>()
        for (match in findAll(source)) {
            if (match.range.first >= startIndex) result.add(match)
        }
        return result.asSequence()
    }

    @KsSymbolName("__kk_regex_matchEntire_flat")
    public external fun matchEntire(input: String): MatchResult?

    public fun matchAt(input: CharSequence, startIndex: Int): MatchResult? {
        val match = find(input, startIndex) ?: return null
        return if (match.range.first == startIndex) match else null
    }

    public fun matchEntire(input: CharSequence): MatchResult? =
        matchEntire(input.regexInputString())

    @KsSymbolName("__kk_regex_containsMatchIn_flat")
    public external fun containsMatchIn(input: String): Boolean

    public fun containsMatchIn(input: CharSequence): Boolean =
        containsMatchIn(input.regexInputString())

    @KsSymbolName("__kk_regex_matches_flat")
    public external fun matches(input: String): Boolean

    public fun matches(input: CharSequence): Boolean =
        matches(input.regexInputString())

    public fun matchesAt(input: CharSequence, startIndex: Int): Boolean =
        matchAt(input, startIndex) != null

    public fun replace(input: String, replacement: String): String =
        __kk_replace_regex(input, this, replacement)

    public fun replace(input: CharSequence, replacement: String): String =
        replace(input.regexInputString(), replacement)

    public fun replaceFirst(input: String, replacement: String): String =
        __kk_replaceFirst_regex(input, this, replacement)

    public fun replaceFirst(input: CharSequence, replacement: String): String =
        replaceFirst(input.regexInputString(), replacement)

    @KsSymbolName("__kk_regex_replace_lambda")
    public external fun replace(input: String, transform: (MatchResult) -> String): String

    public fun replace(
        input: CharSequence,
        transform: (MatchResult) -> CharSequence
    ): String {
        val source = input.regexInputString()
        val matches = findAll(source)
        val result = StringBuilder()
        var cursor = 0
        for (match in matches) {
            val start = match.range.first
            val end = match.range.last + 1
            if (start < cursor) continue
            result.append(source.substring(cursor, start))
            result.append(transform(match))
            cursor = end
        }
        result.append(source.substring(cursor, source.length))
        return result.toString()
    }

    public fun split(input: String, limit: Int = 0): List<String> {
        require(limit >= 0) { "Limit must be non-negative, but was $limit" }
        if (limit == 0) {
            return __kk_split_regex(input, this)
        }
        val result = ArrayList<String>()
        var lastEnd = 0
        var count = 0
        val matches = findAll(input)
        for (match in matches) {
            if (count >= limit - 1) {
                break
            }
            val start = match.range.first
            if (start < lastEnd) {
                continue
            }
            result.add(input.substring(lastEnd, start))
            lastEnd = match.range.last + 1
            count++
        }
        result.add(input.substring(lastEnd, input.length))
        return result
    }

    public fun split(input: CharSequence, limit: Int = 0): List<String> =
        split(input.regexInputString(), limit)

    public fun splitToSequence(input: CharSequence, limit: Int = 0): Sequence<String> =
        split(input.regexInputString(), limit).asSequence()

    override fun toString(): String = __kkRegexPattern(this)
}

@KsSymbolName("__kk_string_replace_regex")
private external fun __kk_replace_regex(input: String, regex: Regex, replacement: String): String

@KsSymbolName("__kk_string_replaceFirst_regex")
private external fun __kk_replaceFirst_regex(input: String, regex: Regex, replacement: String): String

@KsSymbolName("__kk_string_split_regex_flat")
private external fun __kk_split_regex(input: String, regex: Regex): List<String>

private fun CharSequence.regexInputString(): String {
    if (this is String) return this
    val builder = StringBuilder(length)
    var index = 0
    while (index < length) {
        builder.append(this[index])
        index++
    }
    return builder.toString()
}

private fun Regex.findFrom(input: String, startIndex: Int): MatchResult? {
    var match = find(input)
    while (match != null && match.range.first < startIndex) {
        match = match.next()
    }
    return match
}
