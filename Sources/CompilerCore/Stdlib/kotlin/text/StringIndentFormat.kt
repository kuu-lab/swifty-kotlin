package kotlin.text

import kswiftk.internal.*

// String indent and format functions migrated from Swift Runtime
// MIGRATION-TEXT-006

private fun String.splitIntoLines(): List<String> {
    val src = replace("\r\n", "\n").replace("\r", "\n")
    val result = mutableListOf<String>()
    var start = 0
    while (start < __string_struct_get_length(src)) {
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

private fun trimBlankEdges(lines: List<String>): List<String> {
    val n = lines.size
    var start = 0
    var end = n
    while (start < end && lines[start].isBlank()) start++
    while (end > start && lines[end - 1].isBlank()) end--
    if (start >= end) return mutableListOf()
    val result = mutableListOf<String>()
    for (i in start until end) {
        result.add(lines[i])
    }
    return result
}

/**
 * Detects a common minimal indent of all the input lines, removes it from every line and also
 * removes the first and the last lines if they are blank.
 */
public fun String.trimIndent(): String {
    val lines = trimBlankEdges(splitIntoLines())
    if (lines.size == 0) return ""
    var minIndent = -1
    for (line in lines) {
        if (!line.isBlank()) {
            val cnt = line.leadingWhitespaceCount()
            if (minIndent == -1 || cnt < minIndent) minIndent = cnt
        }
    }
    if (minIndent < 0) minIndent = 0
    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\n')
        if (line.isBlank()) {
            sb.append("")
        } else {
            sb.append(line.substring(minIndent))
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
    require(!marginPrefix.isBlank()) { "marginPrefix must be non-blank string." }
    val lines = trimBlankEdges(splitIntoLines())
    if (lines.size == 0) return ""
    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\n')
        var i = 0
        while (i < __string_struct_get_length(line) && (line[i] == ' ' || line[i] == '\t')) i++
        val trimmedLeading = line.substring(i)
        if (trimmedLeading.startsWith(marginPrefix)) {
            sb.append(trimmedLeading.substring(__string_struct_get_length(marginPrefix)))
        } else {
            sb.append(line)
        }
        first = false
    }
    return sb.toString()
}

/**
 * Prepends [indent] to every line of the original string.
 */
public fun String.prependIndent(indent: String = "    "): String {
    val lines = splitIntoLines()
    if (lines.size == 0) return this
    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\n')
        sb.append(indent)
        sb.append(line)
        first = false
    }
    return sb.toString()
}

/**
 * Detects indent (as in [trimIndent]), removes it, then prepends [newIndent] to every line.
 */
public fun String.replaceIndent(newIndent: String = ""): String {
    val lines = trimBlankEdges(splitIntoLines())
    if (lines.size == 0) return ""
    var minIndent = -1
    for (line in lines) {
        if (!line.isBlank()) {
            val cnt = line.leadingWhitespaceCount()
            if (minIndent == -1 || cnt < minIndent) minIndent = cnt
        }
    }
    if (minIndent < 0) minIndent = 0
    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\n')
        if (line.isBlank()) {
            sb.append("")
        } else {
            sb.append(newIndent)
            sb.append(line.substring(minIndent))
        }
        first = false
    }
    return sb.toString()
}

/**
 * Trims leading whitespace followed by [marginPrefix] (as in [trimMargin]),
 * then prepends [newIndent] to every non-margin line.
 */
public fun String.replaceIndentByMargin(newIndent: String = "", marginPrefix: String = "|"): String {
    if (marginPrefix.isBlank()) {
        throw IllegalArgumentException("marginPrefix must be non-blank string.")
    }
    val lines = trimBlankEdges(splitIntoLines())
    if (lines.size == 0) return ""
    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\n')
        var i = 0
        while (i < __string_struct_get_length(line) && (line[i] == ' ' || line[i] == '\t')) i++
        val trimmedLeading = line.substring(i)
        if (trimmedLeading.startsWith(marginPrefix)) {
            sb.append(newIndent)
            sb.append(trimmedLeading.substring(__string_struct_get_length(marginPrefix)))
        } else {
            sb.append(line)
        }
        first = false
    }
    return sb.toString()
}
