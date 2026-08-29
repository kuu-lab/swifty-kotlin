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

    @KsSymbolName("__kk_regex_findAll_flat")
    public external fun findAll(input: String): List<MatchResult>

    @KsSymbolName("__kk_regex_matchEntire_flat")
    public external fun matchEntire(input: String): MatchResult?

    @KsSymbolName("__kk_regex_containsMatchIn_flat")
    public external fun containsMatchIn(input: String): Boolean

    @KsSymbolName("__kk_regex_matches_flat")
    public external fun matches(input: String): Boolean

    public fun replace(input: String, replacement: String): String =
        __kk_replace_regex(input, this, replacement)

    public fun replaceFirst(input: String, replacement: String): String =
        __kk_replaceFirst_regex(input, this, replacement)

    @KsSymbolName("__kk_regex_replace_lambda")
    public external fun replace(input: String, transform: (MatchResult) -> String): String

    public fun split(input: String, limit: Int = 0): List<String> {
        if (limit == 0) {
            return __kk_split_regex(input, this)
        }
        val result = ArrayList<String>()
        var lastEnd = 0
        var count = 0
        val matches = findAll(input)
        for (match in matches) {
            if (limit > 0 && count >= limit - 1) {
                break
            }
            val start = match.range.first
            if (start < lastEnd) {
                continue
            }
            if (match.value.isEmpty() && start == lastEnd && lastEnd < input.length) {
                result.add(input.substring(lastEnd, lastEnd + 1))
                lastEnd++
                continue
            }
            result.add(input.substring(lastEnd, start))
            lastEnd = match.range.last + 1
            count++
        }
        result.add(input.substring(lastEnd, input.length))
        return result
    }
}

@KsSymbolName("__kk_string_replace_regex")
private external fun __kk_replace_regex(input: String, regex: Regex, replacement: String): String

@KsSymbolName("__kk_string_replaceFirst_regex")
private external fun __kk_replaceFirst_regex(input: String, regex: Regex, replacement: String): String

@KsSymbolName("__kk_string_split_regex_flat")
private external fun __kk_split_regex(input: String, regex: Regex): List<String>
