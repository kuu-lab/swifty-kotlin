package kotlin.text

import kswiftk.internal.*

// String indent and format functions migrated from Swift Runtime
// MIGRATION-TEXT-006
//
// Public APIs stay source-backed while delegating to private __kk_* bridges.
// This avoids reviving the legacy public kk_string_* synthetic/member lowering
// surface and keeps the current runtime semantics for multiline raw strings.
//
// String.indent()/indent(n) stay fully pure-Kotlin (not bridged): they have no
// __kk_string_indent* runtime counterpart, so they keep the private
// splitIntoLines()/leadingWhitespaceCount() helpers used by their bodies.

private fun String.normalizeLineSeparators(): String {
    val sb = StringBuilder()
    var i = 0
    while (i < __string_struct_get_length(this)) {
        val c = this[i]
        if (c == '\r') {
            sb.append('\n')
            if (i + 1 < __string_struct_get_length(this) && this[i + 1] == '\n') {
                i++
            }
        } else {
            sb.append(c)
        }
        i++
    }
    return sb.toString()
}

private fun String.splitIntoLines(): List<String> {
    val src = normalizeLineSeparators()
    val result = mutableListOf<String>()
    var start = 0
    while (start <= __string_struct_get_length(src)) {
        val idx = src.indexOf("\n", start)
        if (idx == -1) {
            result.add(src.substring(start))
            break
        }
        result.add(src.substring(start, idx))
        start = idx + 1
    }
    return result
}

private fun String.leadingWhitespaceCount(): Int {
    var count = 0
    while (count < length) {
        val c = this[count]
        if (c != ' ' && c != '\t') break
        count++
    }
    return count
}

private external fun String.__kk_string_trimIndent(): String
private external fun String.__kk_string_trimMargin(marginPrefix: String): String
private external fun String.__kk_string_prependIndent(indent: String): String
private external fun String.__kk_string_replaceIndent(newIndent: String): String
private external fun String.__kk_string_replaceIndentByMargin(newIndent: String, marginPrefix: String): String

/**
 * Detects a common minimal indent of all the input lines, removes it from every line and also
 * removes the first and the last lines if they are blank.
 */
public fun String.trimIndent(): String =
    this.__kk_string_trimIndent()

/**
 * Trims leading whitespace characters followed by [marginPrefix] from every line of a source string
 * and removes the first and the last lines if they are blank.
 */
public fun String.trimMargin(marginPrefix: String = "|"): String =
    this.__kk_string_trimMargin(marginPrefix)

/**
 * Prepends [indent] to every line of the original string.
 *
 * Blank lines shorter than [indent] are replaced by [indent] alone; blank lines
 * that are already at least as long as [indent] are left unchanged. Non-blank
 * lines always get [indent] prepended. Matches kotlin.stdlib `String.prependIndent`.
 */
public fun String.prependIndent(indent: String = "    "): String =
    this.__kk_string_prependIndent(indent)

/**
 * Detects indent (as in [trimIndent]), removes it, then prepends [newIndent] to every line.
 */
public fun String.replaceIndent(newIndent: String = ""): String =
    this.__kk_string_replaceIndent(newIndent)

/**
 * Trims leading whitespace followed by [marginPrefix] (as in [trimMargin]),
 * then prepends [newIndent] to every non-margin line.
 */
public fun String.replaceIndentByMargin(newIndent: String = "", marginPrefix: String = "|"): String =
    this.__kk_string_replaceIndentByMargin(newIndent, marginPrefix)

/**
 * Returns a string with content of this string where each line is indented by 4 spaces.
 */
public fun String.indent(): String = indent(4)

/**
 * Returns a string with content of this string where each line is indented by [n] spaces
 * (or has up to [n] leading spaces removed, when [n] is negative).
 */
public fun String.indent(n: Int): String {
    if (n == 0) return this
    val lines = splitIntoLines()
    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\n')
        if (n > 0) {
            var j = 0
            while (j < n) { sb.append(' '); j++ }
            sb.append(line)
        } else {
            val remove = -n
            val leading = line.leadingWhitespaceCount()
            val drop = if (remove < leading) remove else leading
            sb.append(line.substring(drop))
        }
        first = false
    }
    return sb.toString()
}
