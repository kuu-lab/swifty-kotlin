package kotlin.text

// Regex class API migrated from Swift Runtime
// MIGRATION-REGEX-001
//
// Regex, MatchResult, MatchGroup, MatchGroupCollection, and MatchResult.Destructured
// are backed by NSRegularExpression via the Swift runtime (Sources/Runtime/RuntimeRegex.swift).
// Constructor, find, findAll, and matchEntire are wired via native bridge functions:
//   kk_regex_create / kk_regex_create_with_option / kk_regex_create_with_options
//   kk_regex_find / kk_regex_findAll / kk_regex_matchEntire
// Derived operations (matches, containsMatchIn, replace with transform, split) are
// implemented in Kotlin in terms of those primitives. Future: wire via bundled pipeline.

/**
 * Represents a compiled regular expression.
 * Provides operations to match the pattern against input strings.
 *
 * Backed by NSRegularExpression on macOS. The constructor compiles the given pattern;
 * an invalid pattern substitutes a never-matching expression (Kotlin/JVM throws
 * PatternSyntaxException — this runtime silently degrades to no-match).
 *
 * NOTE: Constructor and primitive members (find, findAll, matchEntire, pattern, options,
 * groupNames) are backed by kk_regex_* bridge functions (MIGRATION-REGEX-001).
 */
// class Regex(val pattern: String) {
//
//     constructor(pattern: String, option: RegexOption) : this(__kk_regex_create_with_option(pattern, option))
//     constructor(pattern: String, options: Set<RegexOption>) : this(__kk_regex_create_with_options(pattern, options))
//
//     /** The original pattern string used to construct this regex. */
//     val pattern: String get() = __kk_regex_pattern()
//
//     /** The set of options specified when this regex was created. */
//     val options: Set<RegexOption> get() = __kk_regex_options()
//
//     /** The set of named capture group names defined in the regex pattern. */
//     val groupNames: Set<String> get() = __kk_regex_group_names()
//
//     /**
//      * Returns the first match of this regular expression in the [input] string,
//      * beginning at [startIndex]. Returns null if there is no match.
//      * NOTE: Backed by kk_regex_find (MIGRATION-REGEX-001).
//      */
//     fun find(input: CharSequence, startIndex: Int = 0): MatchResult? =
//         __kk_regex_find(input.toString())
//
//     /**
//      * Returns a sequence of all occurrences of this regular expression in the [input] string.
//      * NOTE: Backed by kk_regex_findAll (MIGRATION-REGEX-001).
//      */
//     fun findAll(input: CharSequence, startIndex: Int = 0): List<MatchResult> =
//         __kk_regex_findAll(input.toString())
//
//     /**
//      * Attempts to match the entire [input] string against this regular expression.
//      * Returns null if the input string does not match.
//      * NOTE: Backed by kk_regex_matchEntire (MIGRATION-REGEX-001).
//      */
//     fun matchEntire(input: CharSequence): MatchResult? =
//         __kk_regex_matchEntire(input.toString())
//
//     /**
//      * Indicates whether the regular expression matches the entire [input] string.
//      */
//     fun matches(input: CharSequence): Boolean = matchEntire(input) != null
//
//     /**
//      * Indicates whether the regular expression can find at least one match in the [input] string.
//      */
//     fun containsMatchIn(input: CharSequence): Boolean = find(input) != null
//
//     /**
//      * Returns a new string obtained by replacing each occurrence of this regular expression
//      * in the specified [input] string with the specified [replacement] expression.
//      *
//      * The replacement string may contain group references: $0 for the whole match, $1 for the
//      * first group, $groupName for named groups.
//      * NOTE: Backed by kk_string_replace_regex (MIGRATION-REGEX-001).
//      */
//     fun replace(input: CharSequence, replacement: String): String =
//         __kk_string_replace_regex(input.toString(), replacement)
//
//     /**
//      * Returns a new string obtained by replacing each occurrence of this regular expression
//      * in the specified [input] string with the result of the given [transform] function.
//      *
//      * The [transform] function is invoked for each match found in the input, and the return
//      * value of the function replaces that match.
//      * NOTE: Backed by kk_regex_replace_lambda (MIGRATION-REGEX-001).
//      */
//     fun replace(input: CharSequence, transform: (MatchResult) -> CharSequence): String =
//         __kk_regex_replace_lambda(input.toString(), transform)
//
//     /**
//      * Returns a new string obtained by replacing the first occurrence of this regular expression
//      * in the specified [input] string with the specified [replacement] expression.
//      * NOTE: Backed by kk_string_replaceFirst_regex (MIGRATION-REGEX-001).
//      */
//     fun replaceFirst(input: CharSequence, replacement: String): String =
//         __kk_string_replaceFirst_regex(input.toString(), replacement)
//
//     /**
//      * Splits the [input] string around matches of this regular expression.
//      *
//      * @param limit Non-negative value specifying the maximum number of substrings the string can
//      *   be split into. Zero by default means no limit.
//      * NOTE: Backed by kk_string_split_regex (MIGRATION-REGEX-001).
//      */
//     fun split(input: CharSequence, limit: Int = 0): List<String> =
//         __kk_string_split_regex(input.toString())
//
//     companion object {
//         /** Returns a regular expression that matches the specified [literal] string literally. */
//         fun fromLiteral(literal: String): Regex = __kk_regex_from_literal(literal)
//     }
// }

/**
 * Returns `true` if this string matches the given regular expression.
 *
 * NOTE: Backed by kk_string_matches_regex bridge (MIGRATION-REGEX-001).
 * Equivalent to `regex.matches(this)`.
 */
// public fun String.matches(regex: Regex): Boolean = regex.matches(this)

/**
 * Returns a new string obtained by replacing each occurrence of the [regex] with the specified
 * [replacement] string.
 *
 * The replacement string may contain group references: $0 for the whole match, $1 for the first
 * group, $groupName for named groups.
 *
 * NOTE: Backed by kk_string_replace_regex bridge (MIGRATION-REGEX-001).
 */
// public fun String.replace(regex: Regex, replacement: String): String = regex.replace(this, replacement)

/**
 * Returns a new string obtained by replacing each occurrence of the [regex] with the return value
 * of the given function [transform] that takes a [MatchResult].
 *
 * NOTE: Backed by kk_regex_replace_lambda bridge (MIGRATION-REGEX-001).
 */
// public fun String.replace(regex: Regex, transform: (MatchResult) -> CharSequence): String =
//     regex.replace(this, transform)

/**
 * Returns a new string obtained by replacing the first occurrence of the [regex] with the
 * specified [replacement] string.
 *
 * NOTE: Backed by kk_string_replaceFirst_regex bridge (MIGRATION-REGEX-001).
 */
// public fun String.replaceFirst(regex: Regex, replacement: String): String =
//     regex.replaceFirst(this, replacement)

/**
 * Splits this string around matches of the given [regex] regular expression.
 *
 * @param limit Non-negative value specifying the maximum number of substrings the string can be
 *   split into. Zero by default means no limit is set.
 *
 * NOTE: Backed by kk_string_split_regex bridge (MIGRATION-REGEX-001).
 */
// public fun String.split(regex: Regex, limit: Int = 0): List<String> = regex.split(this, limit)

/**
 * Returns a regular expression corresponding to this string.
 *
 * NOTE: Backed by kk_string_toRegex bridge (MIGRATION-REGEX-001).
 */
// public fun String.toRegex(): Regex = Regex(this)

/**
 * Returns a regular expression corresponding to this string with the specified [option].
 *
 * NOTE: Backed by kk_string_toRegex_with_option bridge (MIGRATION-REGEX-001).
 */
// public fun String.toRegex(option: RegexOption): Regex = Regex(this, option)

/**
 * Returns a regular expression corresponding to this string with the specified [options].
 *
 * NOTE: Backed by kk_string_toRegex_with_options bridge (MIGRATION-REGEX-001).
 */
// public fun String.toRegex(options: Set<RegexOption>): Regex = Regex(this, options)

// ---------------------------------------------------------------------------
// MatchResult — backed by RuntimeMatchResultBox (kk_match_result_*)
// ---------------------------------------------------------------------------

/**
 * Represents the results from a single regular expression match.
 *
 * NOTE: Backed by RuntimeMatchResultBox via kk_match_result_* bridge functions
 * (MIGRATION-REGEX-001).
 */
// interface MatchResult {
//     /** The substring from the input string captured by this match. */
//     val value: String
//
//     /** The range of indices in the original string where the match was found. */
//     val range: IntRange
//
//     /**
//      * A list of matched group values. Index 0 is the entire match; index 1..n correspond to
//      * capture groups in the regex.
//      */
//     val groupValues: List<String>
//
//     /** A collection of matched groups, both numbered and named. */
//     val groups: MatchGroupCollection
//
//     /**
//      * Returns the next match in the sequence, or null if there are no more matches.
//      * NOTE: Backed by kk_match_result_next (MIGRATION-REGEX-001).
//      */
//     fun next(): MatchResult?
//
//     /**
//      * A Destructured instance to unpack the capture groups of this match.
//      */
//     val destructured: MatchResult.Destructured
//
//     /**
//      * Provides destructuring access to the capture groups of this MatchResult.
//      * component1() returns groupValues[1], component2() returns groupValues[2], etc.
//      */
//     class Destructured(val match: MatchResult) {
//         operator fun component1(): String = match.groupValues.getOrElse(1) { "" }
//         operator fun component2(): String = match.groupValues.getOrElse(2) { "" }
//         operator fun component3(): String = match.groupValues.getOrElse(3) { "" }
//         operator fun component4(): String = match.groupValues.getOrElse(4) { "" }
//         operator fun component5(): String = match.groupValues.getOrElse(5) { "" }
//         operator fun component6(): String = match.groupValues.getOrElse(6) { "" }
//         operator fun component7(): String = match.groupValues.getOrElse(7) { "" }
//         operator fun component8(): String = match.groupValues.getOrElse(8) { "" }
//         operator fun component9(): String = match.groupValues.getOrElse(9) { "" }
//     }
// }

// ---------------------------------------------------------------------------
// MatchGroup — backed by RuntimeMatchGroupBox (kk_match_group_*)
// ---------------------------------------------------------------------------

/**
 * Represents a matched group in a regular expression result.
 *
 * NOTE: Backed by RuntimeMatchGroupBox via kk_match_group_* bridge functions
 * (MIGRATION-REGEX-001).
 */
// data class MatchGroup(val value: String, val range: IntRange)

// ---------------------------------------------------------------------------
// MatchGroupCollection — backed by RuntimeMatchGroupCollectionBox
// ---------------------------------------------------------------------------

/**
 * A collection of captured groups in a regular expression match.
 * Supports both indexed access ([0], [1], ...) and named access (["groupName"]).
 *
 * NOTE: Backed by RuntimeMatchGroupCollectionBox via kk_match_group_collection_* bridge functions
 * (MIGRATION-REGEX-001).
 */
// abstract class MatchGroupCollection : Collection<MatchGroup?> {
//     abstract operator fun get(index: Int): MatchGroup?
//     abstract operator fun get(name: String): MatchGroup?
// }

// ---------------------------------------------------------------------------
// RegexOption — enum class for compile-time options
// ---------------------------------------------------------------------------

/**
 * Provides enumeration values to use to set regular expression options.
 *
 * NOTE: Backed by synthetic enum class registered in HeaderHelpers+SyntheticRegexStubs.swift
 * with ordinals matching NSRegularExpression.Options (MIGRATION-REGEX-001).
 */
// enum class RegexOption(val value: Int) {
//     IGNORE_CASE(Pattern.CASE_INSENSITIVE),
//     MULTILINE(Pattern.MULTILINE),
//     LITERAL(Pattern.LITERAL),
//     UNIX_LINES(Pattern.UNIX_LINES),
//     COMMENTS(Pattern.COMMENTS),
//     DOT_MATCHES_ALL(Pattern.DOTALL),
//     CANON_EQ(Pattern.CANON_EQ)
// }
