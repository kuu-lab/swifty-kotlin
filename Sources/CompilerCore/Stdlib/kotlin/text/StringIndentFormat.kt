package kotlin.text

// String indent and format functions migrated from Swift Runtime
// MIGRATION-TEXT-006

private fun String.splitIntoLines(): List<String> {
    val src = replace("\r\n", "\n").replace("\r", "\n")
    val result = mutableListOf<String>()
    var start = 0
    while (start < src.length) {
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
    if (lines.isEmpty()) return ""
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
    val lines = trimBlankEdges(splitIntoLines())
    if (lines.isEmpty()) return ""
    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\n')
        var i = 0
        while (i < line.length && (line[i] == ' ' || line[i] == '\t')) i++
        val trimmedLeading = line.substring(i)
        if (trimmedLeading.startsWith(marginPrefix)) {
            sb.append(trimmedLeading.substring(marginPrefix.length))
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
    if (lines.isEmpty()) return this
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
    if (lines.isEmpty()) return ""
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
    if (lines.isEmpty()) return ""
    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\n')
        var i = 0
        while (i < line.length && (line[i] == ' ' || line[i] == '\t')) i++
        val trimmedLeading = line.substring(i)
        if (trimmedLeading.startsWith(marginPrefix)) {
            sb.append(newIndent)
            sb.append(trimmedLeading.substring(marginPrefix.length))
        } else {
            sb.append(line)
        }
        first = false
    }
    return sb.toString()
}

private fun digitValue(c: Char): Int {
    return when (c) {
        '0' -> 0
        '1' -> 1
        '2' -> 2
        '3' -> 3
        '4' -> 4
        '5' -> 5
        '6' -> 6
        '7' -> 7
        '8' -> 8
        '9' -> 9
        else -> -1
    }
}

private fun appendPadded(sb: StringBuilder, value: String, width: Int, leftAlign: Boolean, zeroPad: Boolean) {
    val padding = width - value.length
    if (padding <= 0) {
        sb.append(value)
        return
    }
    val padChar = if (zeroPad && !leftAlign) '0' else ' '
    if (leftAlign) {
        sb.append(value)
        var p = 0
        while (p < padding) {
            sb.append(' ')
            p++
        }
    } else {
        var p = 0
        while (p < padding) {
            sb.append(padChar)
            p++
        }
        sb.append(value)
    }
}

/**
 * Uses this string as a format string and returns a string obtained by substituting
 * the specified arguments, using the default locale.
 */
public fun String.format(vararg args: Any?): String {
    val argList = mutableListOf<Any?>()
    for (a in args) argList.add(a)
    val sb = StringBuilder()
    var i = 0
    var argIndex = 0
    while (i < length) {
        val c = this[i]
        if (c != '%') {
            sb.append(c)
            i++
            continue
        }
        i++
        if (i >= length) {
            sb.append('%')
            break
        }
        var leftAlign = false
        var zeroPad = false
        var width = 0
        if (this[i] == '-') {
            leftAlign = true
            i++
        }
        if (i < length && this[i] == '0' && digitValue(this[i]) == 0) {
            zeroPad = true
            i++
        }
        while (i < length && digitValue(this[i]) != -1) {
            width = width * 10 + digitValue(this[i])
            i++
        }
        if (i < length && this[i] == '.') {
            i++
            while (i < length && digitValue(this[i]) != -1) i++
        }
        if (i >= length) {
            sb.append('%')
            break
        }
        val spec = this[i]
        i++
        when (spec) {
            '%' -> sb.append('%')
            'n' -> sb.append('\n')
            's' -> {
                val value = if (argIndex < argList.size) (argList[argIndex]?.toString() ?: "null") else ""
                argIndex++
                appendPadded(sb, value, width, leftAlign, false)
            }
            'S' -> {
                val value = if (argIndex < argList.size) (argList[argIndex]?.toString() ?: "null") else ""
                argIndex++
                appendPadded(sb, value.uppercase(), width, leftAlign, false)
            }
            'd' -> {
                val value = if (argIndex < argList.size) (argList[argIndex]?.toString() ?: "0") else "0"
                argIndex++
                appendPadded(sb, value, width, leftAlign, zeroPad)
            }
            'f' -> {
                val value = if (argIndex < argList.size) (argList[argIndex]?.toString() ?: "0.0") else "0.0"
                argIndex++
                appendPadded(sb, value, width, leftAlign, zeroPad)
            }
            'b' -> {
                val value = if (argIndex < argList.size) (argList[argIndex]?.toString() ?: "false") else "false"
                argIndex++
                appendPadded(sb, value, width, leftAlign, false)
            }
            'B' -> {
                val value = if (argIndex < argList.size) (argList[argIndex]?.toString() ?: "false") else "false"
                argIndex++
                appendPadded(sb, value.uppercase(), width, leftAlign, false)
            }
            'c', 'C' -> {
                val value = if (argIndex < argList.size) (argList[argIndex]?.toString() ?: "") else ""
                argIndex++
                appendPadded(sb, value, width, leftAlign, false)
            }
            else -> {
                sb.append('%')
                sb.append(spec)
            }
        }
    }
    return sb.toString()
}
