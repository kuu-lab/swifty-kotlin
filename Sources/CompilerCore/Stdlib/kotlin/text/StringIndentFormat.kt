package kotlin.text

// String indent and format functions migrated from Swift Runtime.
// MIGRATION-TEXT-006

internal fun String.normalizeLineSeparators(): String {
    val sb = StringBuilder()
    var i = 0
    while (i < this.length) {
        val c = this[i]
        if (c == '\r') {
            sb.append('\n')
            if (i + 1 < this.length && this[i + 1] == '\n') {
                i++
            }
        } else {
            sb.append(c)
        }
        i++
    }
    return sb.toString()
}
internal fun String.splitIntoLines(): List<String> {
    val src = normalizeLineSeparators()
    val result = mutableListOf<String>()
    var start = 0
    while (start <= src.length) {
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
        if (!c.isWhitespace()) return false
        i++
    }
    return true
}

private fun String.leadingWhitespaceCount(): Int {
    var count = 0
    while (count < length) {
        val c = this[count]
        if (!c.isWhitespace()) break
        count++
    }
    return count
}

private fun String.trimBlankEdges(): List<String> {
    val lines = splitIntoLines()
    var start = 0
    var end = lines.size
    if (start < end && lines[start].isBlankLine()) start++
    if (end > start && lines[end - 1].isBlankLine()) end--
    return lines.subList(start, end)
}

public fun String.trimIndent(): String {
    return replaceIndent("")
}

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

public fun String.trimMargin(marginPrefix: String = "|"): String {
    return replaceIndentByMargin("", marginPrefix)
}

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
        val firstNonWhitespaceIndex = line.indexOfFirst { !it.isWhitespace() }
        if (firstNonWhitespaceIndex >= 0 && line.startsWith(marginPrefix, firstNonWhitespaceIndex)) {
            sb.append(newIndent)
            sb.append(line.substring(firstNonWhitespaceIndex + marginPrefix.length))
        } else {
            sb.append(line)
        }
        first = false
    }
    return sb.toString()
}

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
