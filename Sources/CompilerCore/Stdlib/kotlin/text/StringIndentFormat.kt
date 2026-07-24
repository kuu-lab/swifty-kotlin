package kotlin.text

import kswiftk.internal.*

// String indent and format functions migrated from Swift Runtime.
// MIGRATION-TEXT-006
//
// Public APIs are now fully implemented in Kotlin. The legacy `__kk_string_*`
// runtime bridges have been removed as part of the KSP-302 cleanup.

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

private fun String.isBlankLine(): Boolean {
    var i = 0
    while (i < length) {
        val c = this[i]
        if (c != ' ' && c != '\t') return false
        i++
    }
    return true
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

private fun String.trimBlankEdges(): List<String> {
    val lines = splitIntoLines()
    var start = 0
    var end = lines.size
    while (start < end && lines[start].isBlankLine()) start++
    while (end > start && lines[end - 1].isBlankLine()) end--
    return lines.subList(start, end)
}

/**
 * Detects a common minimal indent of all the input lines, removes it from every line and also
 * removes the first and the last lines if they are blank.
 */
public fun String.trimIndent(): String {
    return replaceIndent("")
}

/**
 * Detects indent (as in [trimIndent]), removes it, then prepends [newIndent] to every line.
 */
public fun String.replaceIndent(newIndent: String = ""): String {
    val lines = trimBlankEdges()
    if (lines.isEmpty()) return ""

    var minimumIndent = Int.MAX_VALUE
    for (line in lines) {
        if (!line.isBlankLine()) {
            val indent = line.leadingWhitespaceCount()
            if (indent < minimumIndent) {
                minimumIndent = indent
            }
        }
    }
    if (minimumIndent == Int.MAX_VALUE) {
        minimumIndent = 0
    }

    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\n')
        sb.append(newIndent)
        if (minimumIndent < line.length) {
            sb.append(line.substring(minimumIndent))
        }
        first = false
    }
    return sb.toString()
}

/**
 * Trims leading whitespace characters followed by [marginPrefix] from every line of a source string
 * and removes the first and the last lines if they are blank.
 */
public fun String.trimMargin(marginPrefix: String = "|"): String {
    return replaceIndentByMargin("", marginPrefix)
}

/**
 * Trims leading whitespace followed by [marginPrefix] (as in [trimMargin]),
 * then prepends [newIndent] to every non-margin line.
 */
public fun String.replaceIndentByMargin(newIndent: String = "", marginPrefix: String = "|"): String {
    if (marginPrefix.isBlankLine()) {
        throw IllegalArgumentException("marginPrefix must be non-blank string.")
    }
    val lines = trimBlankEdges()
    if (lines.isEmpty()) return ""

    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\n')
        val trimmedLeading = line.dropWhile { it == ' ' || it == '\t' }
        if (trimmedLeading.startsWith(marginPrefix)) {
            sb.append(newIndent)
            sb.append(trimmedLeading.removePrefix(marginPrefix))
        } else {
            sb.append(line)
        }
        first = false
    }
    return sb.toString()
}

/**
 * Prepends [indent] to every line of the original string.
 *
 * Blank lines shorter than [indent] are replaced by [indent] alone; blank lines
 * that are already at least as long as [indent] are left unchanged. Non-blank
 * lines always get [indent] prepended.
 */
public fun String.prependIndent(indent: String = "    "): String {
    val lines = splitIntoLines()
    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\n')
        if (line.isBlankLine()) {
            if (line.length < indent.length) {
                sb.append(indent)
            } else {
                sb.append(line)
            }
        } else {
            sb.append(indent)
            sb.append(line)
        }
        first = false
    }
    return sb.toString()
}

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
    if (n > 0) {
        val indentBuilder = StringBuilder()
        var j = 0
        while (j < n) {
            indentBuilder.append(' ')
            j++
        }
        val indent = indentBuilder.toString()
        for (line in lines) {
            if (!first) sb.append('\n')
            if (line.isBlankLine() && line.length < indent.length) {
                sb.append(indent)
            } else {
                sb.append(indent)
                sb.append(line)
            }
            first = false
        }
    } else {
        val remove = -n
        for (line in lines) {
            if (!first) sb.append('\n')
            val leading = line.leadingWhitespaceCount()
            val drop = if (remove < leading) remove else leading
            sb.append(line.substring(drop))
            first = false
        }
    }
    return sb.toString()
}
