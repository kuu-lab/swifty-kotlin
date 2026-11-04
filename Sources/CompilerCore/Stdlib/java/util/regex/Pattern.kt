package java.util.regex

import kotlin.text.Regex
import kotlin.text.RegexOption
import kotlin.text.escape
import kotlin.text.options

public class Pattern internal constructor(
    internal val regex: Regex,
    private val patternText: String,
    private val matchFlags: Int
) {
    /**
     * Number of capturing groups this pattern declares, matching the JDK's
     * `Pattern.capturingGroupCount`. A LITERAL pattern is all quoted text and
     * captures nothing.
     */
    internal val groupCount: Int = if (RegexOption.LITERAL in regex.options) {
        0
    } else {
        countCapturingGroups(patternText, comments = RegexOption.COMMENTS in regex.options)
    }

    public fun matcher(input: CharSequence): Matcher = Matcher(this, input.toString())

    public fun pattern(): String = patternText

    public fun flags(): Int = matchFlags

    public fun split(input: CharSequence): Array<String> = split(input, 0)

    public fun split(input: CharSequence, limit: Int): Array<String> {
        val source = input.toString()
        if (limit == 1) return arrayOf(source)

        val parts = mutableListOf<String>()
        var lastEnd = 0
        var splitCount = 0
        for (match in regex.findAll(source)) {
            if (limit > 0 && splitCount >= limit - 1) break
            val start = match.range.first
            val end = match.range.last + 1

            // A zero-width match at the start does not produce a leading empty part.
            if (start == 0 && end == 0) continue

            parts.add(source.substring(lastEnd, start))
            lastEnd = end
            splitCount++
        }

        if (splitCount == 0) return arrayOf(source)
        parts.add(source.substring(lastEnd))

        if (limit == 0) {
            while (parts.isNotEmpty() && parts[parts.size - 1].isEmpty()) {
                parts.removeAt(parts.size - 1)
            }
        }
        return parts.toTypedArray()
    }

    override fun toString(): String = patternText

    /**
     * Counts capturing groups by scanning the pattern text. `(` opens a
     * capturing group unless it starts a `(?…` form; among those, only the
     * named-capture `(?<name>` counts (`(?<=` / `(?<!` are lookbehind).
     * Escaped spans (`\x`, `\Q…\E`), character classes, and `#` comments in
     * COMMENTS mode contribute no groups.
     */
    private fun countCapturingGroups(pattern: String, comments: Boolean): Int {
        var count = 0
        var index = 0
        var quoted = false
        while (index < pattern.length) {
            val char = pattern[index]
            when {
                quoted -> {
                    if (char == '\\' && index + 1 < pattern.length && pattern[index + 1] == 'E') {
                        quoted = false
                        index++
                    }
                }
                char == '\\' -> {
                    if (index + 1 < pattern.length && pattern[index + 1] == 'Q') {
                        quoted = true
                    }
                    index++
                }
                comments && char == '#' -> {
                    while (index < pattern.length && pattern[index] != '\n') index++
                }
                char == '[' -> {
                    index++
                    if (index < pattern.length && pattern[index] == '^') index++
                    if (index < pattern.length && pattern[index] == ']') index++
                    while (index < pattern.length && pattern[index] != ']') {
                        if (pattern[index] == '\\') index++
                        index++
                    }
                }
                char == '(' -> {
                    val isNamedCapture = index + 3 < pattern.length &&
                        pattern[index + 1] == '?' && pattern[index + 2] == '<' &&
                        pattern[index + 3] != '=' && pattern[index + 3] != '!'
                    if (isNamedCapture || index + 1 >= pattern.length || pattern[index + 1] != '?') {
                        count++
                    }
                }
            }
            index++
        }
        return count
    }

    public companion object {
        public const val UNIX_LINES: Int = 0x01
        public const val CASE_INSENSITIVE: Int = 0x02
        public const val COMMENTS: Int = 0x04
        public const val MULTILINE: Int = 0x08
        public const val LITERAL: Int = 0x10
        public const val DOTALL: Int = 0x20
        public const val UNICODE_CASE: Int = 0x40
        public const val CANON_EQ: Int = 0x80
        public const val UNICODE_CHARACTER_CLASS: Int = 0x100

        public fun compile(pattern: String): Pattern = compile(pattern, 0)

        public fun compile(pattern: String, flags: Int): Pattern {
            if ((flags and 0x1FF.inv()) != 0) {
                throw IllegalArgumentException("Unknown regex flag: $flags")
            }
            val effectiveFlags = if ((flags and UNICODE_CHARACTER_CLASS) != 0) {
                flags or UNICODE_CASE
            } else {
                flags
            }
            // `kotlin.text.RegexOption` has no UNICODE_CHARACTER_CLASS member
            // (matching the real Kotlin stdlib), so embed the equivalent (?U)
            // inline flag instead. Skipped under LITERAL, where the whole
            // pattern is literal text and the flag would be quoted anyway.
            val effectivePattern = if ((flags and UNICODE_CHARACTER_CLASS) != 0 && (flags and LITERAL) == 0) {
                "(?U)" + pattern
            } else {
                pattern
            }
            val options = mutableSetOf<RegexOption>()
            if ((effectiveFlags and CASE_INSENSITIVE) != 0) options.add(RegexOption.IGNORE_CASE)
            if ((effectiveFlags and MULTILINE) != 0) options.add(RegexOption.MULTILINE)
            if ((effectiveFlags and LITERAL) != 0) options.add(RegexOption.LITERAL)
            if ((effectiveFlags and UNIX_LINES) != 0) options.add(RegexOption.UNIX_LINES)
            if ((effectiveFlags and COMMENTS) != 0) options.add(RegexOption.COMMENTS)
            if ((effectiveFlags and DOTALL) != 0) options.add(RegexOption.DOT_MATCHES_ALL)
            if ((effectiveFlags and CANON_EQ) != 0) options.add(RegexOption.CANON_EQ)

            return Pattern(Regex(effectivePattern, options), pattern, effectiveFlags)
        }

        public fun matches(regex: String, input: CharSequence): Boolean =
            compile(regex).matcher(input).matches()

        public fun quote(s: String): String = Regex.escape(s)

        internal fun fromRegex(regex: Regex): Pattern =
            Pattern(regex, regex.toString(), flagsFor(regex.options))

        private fun flagsFor(options: Set<RegexOption>): Int {
            var flags = 0
            for (option in options) {
                flags = flags or when (option) {
                    RegexOption.IGNORE_CASE -> CASE_INSENSITIVE or UNICODE_CASE
                    RegexOption.MULTILINE -> MULTILINE
                    RegexOption.LITERAL -> LITERAL
                    RegexOption.UNIX_LINES -> UNIX_LINES
                    RegexOption.COMMENTS -> COMMENTS
                    RegexOption.DOT_MATCHES_ALL -> DOTALL
                    RegexOption.CANON_EQ -> CANON_EQ
                }
            }
            return flags
        }
    }
}
