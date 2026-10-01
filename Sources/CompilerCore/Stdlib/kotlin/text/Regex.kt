package kotlin.text

import kotlin.internal.KsSymbolName
import kotlin.sequences.emptySequence
import kotlin.sequences.generateSequence

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
    private external fun find(input: String): MatchResult?

    // Keep the CharSequence API as explicit arity overloads. The String bridge
    // above and a defaulted source-backed parameter can otherwise be exposed as
    // one unstable candidate shape when the call is imported from a .kklib.
    public fun find(input: CharSequence): MatchResult? = find(input, 0)

    public fun find(input: CharSequence, startIndex: Int): MatchResult? {
        val source = input.regexInputString()
        require(startIndex >= 0 && startIndex <= source.length) {
            "Start index out of bounds: $startIndex"
        }
        var match = find(source)
        while (match != null && match.range.first < startIndex) {
            match = match.next()
        }
        return match
    }

    public fun findAll(input: CharSequence): Sequence<MatchResult> = findAll(input, 0)

    public fun findAll(input: CharSequence, startIndex: Int): Sequence<MatchResult> {
        val source = input.regexInputString()
        require(startIndex >= 0 && startIndex <= source.length) {
            "Start index out of bounds: $startIndex"
        }
        var first = find(source)
        while (first != null && first.range.first < startIndex) {
            first = first.next()
        }
        if (first == null) return emptySequence<MatchResult>()
        return generateSequence<MatchResult>(first) { it.next() }
    }

    public fun matchAt(input: CharSequence, index: Int): MatchResult? {
        val match = find(input, index) ?: return null
        return if (match.range.first == index) match else null
    }

    public fun matchEntire(input: CharSequence): MatchResult? =
        __kkRegexMatchEntire(this, input.regexInputString())

    public fun containsMatchIn(input: CharSequence): Boolean =
        __kkRegexContainsMatchIn(this, input.regexInputString())

    public fun matches(input: CharSequence): Boolean =
        __kkRegexMatches(this, input.regexInputString())

    public fun matchesAt(input: CharSequence, index: Int): Boolean =
        matchAt(input, index) != null

    public fun replace(input: CharSequence, replacement: String): String =
        regexReplace(this, input.regexInputString(), replacement)

    public fun replaceFirst(input: CharSequence, replacement: String): String =
        regexReplaceFirst(this, input.regexInputString(), replacement)

    public fun replace(
        input: CharSequence,
        transform: (MatchResult) -> CharSequence
    ): String {
        val source = input.regexInputString()
        val result = StringBuilder()
        var cursor = 0
        for (match in findAll(source)) {
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

    public fun split(input: CharSequence, limit: Int = 0): List<String> =
        regexSplit(this, input.regexInputString(), limit)

    public fun splitToSequence(input: CharSequence, limit: Int = 0): Sequence<String> =
        regexSplit(this, input.regexInputString(), limit).asSequence()

    // Constructor parameter `pattern` is not a property; naming this
    // `= pattern` would bind to that parameter slot (uninitialized / null)
    // instead of the `Regex.pattern` extension.
    override fun toString(): String = __kkRegexPattern(this)
}

@KsSymbolName("__kk_regex_matchEntire_flat")
private external fun __kkRegexMatchEntire(regex: Regex, input: String): MatchResult?

@KsSymbolName("__kk_regex_containsMatchIn_flat")
private external fun __kkRegexContainsMatchIn(regex: Regex, input: String): Boolean

@KsSymbolName("__kk_regex_matches_flat")
private external fun __kkRegexMatches(regex: Regex, input: String): Boolean

private fun regexReplace(regex: Regex, input: String, replacement: String): String =
    __kk_replace_regex(input, regex, replacement)

private fun regexReplaceFirst(regex: Regex, input: String, replacement: String): String =
    __kk_replaceFirst_regex(input, regex, replacement)

private fun regexSplit(regex: Regex, input: String, limit: Int = 0): List<String> {
    requireNonNegativeLimit(limit)
    if (limit == 0) {
        return __kk_split_regex(input, regex)
    }
    val result = ArrayList<String>()
    var lastStart = 0
    var count = 0
    for (match in regex.findAll(input)) {
        if (count >= limit - 1) {
            break
        }
        result.add(input.substring(lastStart, match.range.first))
        lastStart = match.range.last + 1
        count++
    }
    result.add(input.substring(lastStart, input.length))
    return result
}

internal fun requireNonNegativeLimit(limit: Int) =
    require(limit >= 0) { "Limit must be non-negative, but was $limit" }

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
