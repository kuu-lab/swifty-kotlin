package kotlin.text

import kswiftk.internal.*

// String indent and format functions migrated from Swift Runtime
// MIGRATION-TEXT-006

/**
 * Detects a common minimal indent of all the input lines, removes it from every line and also
 * removes the first and the last lines if they are blank.
 */
public fun String.trimIndent(): String {
    val lines = mutableListOf<String>()
    var currentLine = StringBuilder()
    var scan = 0
    var lastWasLineBreak = false
    while (scan < length) {
        val c = this[scan]
        if (c == '\r') {
            lines.add(currentLine.toString())
            currentLine = StringBuilder()
            lastWasLineBreak = true
            if (scan + 1 < length && this[scan + 1] == '\n') scan++
        } else if (c == '\n') {
            lines.add(currentLine.toString())
            currentLine = StringBuilder()
            lastWasLineBreak = true
        } else {
            currentLine.append(c)
            lastWasLineBreak = false
        }
        scan++
    }
    if (!lastWasLineBreak && length > 0) lines.add(currentLine.toString())
    var start = 0
    var end = lines.size
    while (start < end && lines[start].isBlank()) start++
    while (end > start && lines[end - 1].isBlank()) end--
    if (start >= end) return ""

    var minIndent = -1
    var i = start
    while (i < end) {
        val line = lines[i]
        if (!line.isBlank()) {
            var cnt = 0
            while (cnt < line.length) {
                val c = line[cnt]
                if (c != ' ' && c != '\t') break
                cnt++
            }
            if (minIndent == -1 || cnt < minIndent) minIndent = cnt
        }
        i++
    }
    if (minIndent < 0) minIndent = 0
    val sb = StringBuilder()
    var first = true
    i = start
    while (i < end) {
        val line = lines[i]
        if (!first) sb.append('\n')
        if (line.isBlank()) {
            sb.append("")
        } else {
            sb.append(line.substring(minIndent))
        }
        first = false
        i++
    }
    return sb.toString()
}

/**
 * Trims leading whitespace characters followed by [marginPrefix] from every line of a source string
 * and removes the first and the last lines if they are blank.
 */
public fun String.trimMargin(marginPrefix: String = "|"): String {
    require(!marginPrefix.isBlank()) { "marginPrefix must be non-blank string." }
    val lines = mutableListOf<String>()
    var currentLine = StringBuilder()
    var scan = 0
    var lastWasLineBreak = false
    while (scan < length) {
        val c = this[scan]
        if (c == '\r') {
            lines.add(currentLine.toString())
            currentLine = StringBuilder()
            lastWasLineBreak = true
            if (scan + 1 < length && this[scan + 1] == '\n') scan++
        } else if (c == '\n') {
            lines.add(currentLine.toString())
            currentLine = StringBuilder()
            lastWasLineBreak = true
        } else {
            currentLine.append(c)
            lastWasLineBreak = false
        }
        scan++
    }
    if (!lastWasLineBreak && length > 0) lines.add(currentLine.toString())
    var start = 0
    var end = lines.size
    while (start < end && lines[start].isBlank()) start++
    while (end > start && lines[end - 1].isBlank()) end--
    if (start >= end) return ""

    val sb = StringBuilder()
    var first = true
    var lineIndex = start
    while (lineIndex < end) {
        val line = lines[lineIndex]
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
        lineIndex++
    }
    return sb.toString()
}

/**
 * Prepends [indent] to every line of the original string.
 */
public fun String.prependIndent(indent: String = "    "): String {
    val lines = mutableListOf<String>()
    var currentLine = StringBuilder()
    var scan = 0
    var lastWasLineBreak = false
    while (scan < length) {
        val c = this[scan]
        if (c == '\r') {
            lines.add(currentLine.toString())
            currentLine = StringBuilder()
            lastWasLineBreak = true
            if (scan + 1 < length && this[scan + 1] == '\n') scan++
        } else if (c == '\n') {
            lines.add(currentLine.toString())
            currentLine = StringBuilder()
            lastWasLineBreak = true
        } else {
            currentLine.append(c)
            lastWasLineBreak = false
        }
        scan++
    }
    if (!lastWasLineBreak && length > 0) lines.add(currentLine.toString())
    if (lines.size == 0) return this
    val sb = StringBuilder()
    var first = true
    var i = 0
    while (i < lines.size) {
        val line = lines[i]
        if (!first) sb.append('\n')
        sb.append(indent)
        sb.append(line)
        first = false
        i++
    }
    return sb.toString()
}

/**
 * Detects indent (as in [trimIndent]), removes it, then prepends [newIndent] to every line.
 */
public fun String.replaceIndent(newIndent: String = ""): String {
    val lines = mutableListOf<String>()
    var currentLine = StringBuilder()
    var scan = 0
    var lastWasLineBreak = false
    while (scan < length) {
        val c = this[scan]
        if (c == '\r') {
            lines.add(currentLine.toString())
            currentLine = StringBuilder()
            lastWasLineBreak = true
            if (scan + 1 < length && this[scan + 1] == '\n') scan++
        } else if (c == '\n') {
            lines.add(currentLine.toString())
            currentLine = StringBuilder()
            lastWasLineBreak = true
        } else {
            currentLine.append(c)
            lastWasLineBreak = false
        }
        scan++
    }
    if (!lastWasLineBreak && length > 0) lines.add(currentLine.toString())
    var start = 0
    var end = lines.size
    while (start < end && lines[start].isBlank()) start++
    while (end > start && lines[end - 1].isBlank()) end--
    if (start >= end) return ""

    var minIndent = -1
    var i = start
    while (i < end) {
        val line = lines[i]
        if (!line.isBlank()) {
            var cnt = 0
            while (cnt < line.length) {
                val c = line[cnt]
                if (c != ' ' && c != '\t') break
                cnt++
            }
            if (minIndent == -1 || cnt < minIndent) minIndent = cnt
        }
        i++
    }
    if (minIndent < 0) minIndent = 0
    val sb = StringBuilder()
    var first = true
    i = start
    while (i < end) {
        val line = lines[i]
        if (!first) sb.append('\n')
        if (line.isBlank()) {
            sb.append("")
        } else {
            sb.append(newIndent)
            sb.append(line.substring(minIndent))
        }
        first = false
        i++
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
    val lines = mutableListOf<String>()
    var currentLine = StringBuilder()
    var scan = 0
    var lastWasLineBreak = false
    while (scan < length) {
        val c = this[scan]
        if (c == '\r') {
            lines.add(currentLine.toString())
            currentLine = StringBuilder()
            lastWasLineBreak = true
            if (scan + 1 < length && this[scan + 1] == '\n') scan++
        } else if (c == '\n') {
            lines.add(currentLine.toString())
            currentLine = StringBuilder()
            lastWasLineBreak = true
        } else {
            currentLine.append(c)
            lastWasLineBreak = false
        }
        scan++
    }
    if (!lastWasLineBreak && length > 0) lines.add(currentLine.toString())
    var start = 0
    var end = lines.size
    while (start < end && lines[start].isBlank()) start++
    while (end > start && lines[end - 1].isBlank()) end--
    if (start >= end) return ""

    val sb = StringBuilder()
    var first = true
    var lineIndex = start
    while (lineIndex < end) {
        val line = lines[lineIndex]
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
        lineIndex++
    }
    return sb.toString()
}

public fun String.indent(): String = indent(4)

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
