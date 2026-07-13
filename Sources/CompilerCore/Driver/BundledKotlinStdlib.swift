/// Residual bundled Kotlin source for stdlib functions not yet migrated to
/// standalone `.kt` files under `Sources/CompilerCore/Stdlib/`.
///
/// As functions are migrated to `.kt` files (auto-discovered by
/// `LoadSourcesPhase.injectBundledStdlib`), remove them from here.
enum BundledKotlinStdlib {
    // count / any / all / none / sumOf / maxByOrNull / minByOrNull are not yet
    // in standalone .kt files. The remaining collection HOFs (search, aggregate,
    // filter, sorting, set) have been migrated to ListSearchHOF.kt,
    // ListAggregateHOF.kt, ListFilterHOF.kt, ListSortingHOF.kt, and SetHOF.kt
    // respectively.
    static let kotlinCollectionsSource = """
package kotlin.collections

import kotlin.internal.KsSymbolName

@KsSymbolName("kk_list_of")
private external fun <T> __kk_list_of(array: Any?, count: Int): MutableList<T>

public fun <T : Any> listOfNotNull(vararg elements: T?): List<T> {
    val result: MutableList<T> = __kk_list_of(null, 0)
    for (element in elements) {
        if (element != null) result.add(element)
    }
    return result
}

public fun <T> List<T>.count(predicate: (T) -> Boolean): Int {
    var count = 0
    var i = 0
    while (i < size) { if (predicate(this[i])) count += 1; i += 1 }
    return count
}

public fun <T> List<T>.any(predicate: (T) -> Boolean): Boolean {
    var i = 0
    while (i < size) { if (predicate(this[i])) return true; i += 1 }
    return false
}

public fun <T> List<T>.all(predicate: (T) -> Boolean): Boolean {
    var i = 0
    while (i < size) { if (!predicate(this[i])) return false; i += 1 }
    return true
}

public fun <T> List<T>.none(predicate: (T) -> Boolean): Boolean {
    var i = 0
    while (i < size) { if (predicate(this[i])) return false; i += 1 }
    return true
}

public fun <T> List<T>.sumOf(selector: (T) -> Int): Int {
    var sum = 0
    var i = 0
    while (i < size) { sum += selector(this[i]); i += 1 }
    return sum
}

public fun <T, R : Comparable<R>> List<T>.maxByOrNull(selector: (T) -> R): T? {
    if (length == 0) return null
    var bestElem = this[0]
    var bestKey = selector(bestElem)
    var i = 1
    while (i < size) {
        val elem = this[i]
        val key = selector(elem)
        if (key > bestKey) { bestElem = elem; bestKey = key }
        i += 1
    }
    return bestElem
}

public fun <T, R : Comparable<R>> List<T>.minByOrNull(selector: (T) -> R): T? {
    if (length == 0) return null
    var bestElem = this[0]
    var bestKey = selector(bestElem)
    var i = 1
    while (i < size) {
        val elem = this[i]
        val key = selector(elem)
        if (key < bestKey) { bestElem = elem; bestKey = key }
        i += 1
    }
    return bestElem
}
"""

    // repeat / reversed / padStart / padEnd are pure Kotlin but not yet in .kt files.
    // encodeToByteArray / decodeToString delegate to C-bridge primitives (__kk_*).
    // The case-conversion functions (lowercase, uppercase, capitalize, replaceFirstChar,
    // locale variants) have been migrated to StringCaseConversion.kt.
    static let kotlinTextSource = """
package kotlin.text

fun String.repeat(count: Int): String {
    if (count < 0) throw IllegalArgumentException("Count 'n' must be non-negative, but was $count.")
    val sb = StringBuilder()
    var i = 0
    while (i < count) { sb.append(this); i += 1 }
    return sb.toString()
}

fun String.reversed(): String {
    val len = this.length
    val sb = StringBuilder()
    var i = len - 1
    while (i >= 0) { sb.append(this[i]); i -= 1 }
    return sb.toString()
}

fun String.padStart(length: Int, padChar: Char = ' '): String {
    val padding = length - this.length
    if (padding <= 0) return this
    val sb = StringBuilder()
    var i = 0
    while (i < padding) { sb.append(padChar); i += 1 }
    sb.append(this)
    return sb.toString()
}

fun String.padEnd(length: Int, padChar: Char = ' '): String {
    val padding = length - this.length
    if (padding <= 0) return this
    val sb = StringBuilder()
    sb.append(this)
    var i = 0
    while (i < padding) { sb.append(padChar); i += 1 }
    return sb.toString()
}

// MIGRATION-TEXT-007: String.encodeToByteArray — delegate to private C-bridge primitives

fun String.encodeToByteArray(): ByteArray = this.__kk_encodeToByteArray()

fun String.encodeToByteArray(startIndex: Int, endIndex: Int): ByteArray =
    this.__kk_encodeToByteArray_range(startIndex, endIndex)

fun String.encodeToByteArray(charset: Charset): ByteArray =
    this.__kk_encodeToByteArray_charset(charset)

// MIGRATION-TEXT-007: ByteArray.decodeToString — delegate to private C-bridge primitives

fun ByteArray.decodeToString(): String = this.__kk_decodeToString()

fun ByteArray.decodeToString(charset: Charset): String =
    this.__kk_decodeToString_charset(charset)

fun ByteArray.decodeToString(startIndex: Int, endIndex: Int): String =
    this.__kk_decodeToString_range(startIndex, endIndex)

fun ByteArray.decodeToString(startIndex: Int, endIndex: Int, throwOnInvalidSequence: Boolean): String =
    this.__kk_decodeToString_range_throw(startIndex, endIndex, throwOnInvalidSequence)

// MIGRATION-TEXT-006: indent & margin helpers

private fun String.kk_drop(n: Int): String {
    val sb = StringBuilder()
    var i = n
    while (i < length) { sb.append(this[i]); i++ }
    return sb.toString()
}

private fun String.hasPrefix(prefix: String): Boolean {
    if (prefix.length > length) return false
    var i = 0
    while (i < prefix.length) {
        if (this[i] != prefix[i]) return false
        i++
    }
    return true
}

private fun String.splitIntoLines(): List<String> {
    val result = mutableListOf<String>()
    val sb = StringBuilder()
    var i = 0
    while (i < length) {
        val c = this[i]
        if (c == '\\n') {
            result.add(sb.toString())
            sb.clear()
        } else if (c == '\\r') {
            result.add(sb.toString())
            sb.clear()
            if (i + 1 < length && this[i + 1] == '\\n') i++
        } else {
            sb.append(c)
        }
        i++
    }
    result.add(sb.toString())
    return result
}

private fun String.leadingWhitespaceCount(): Int {
    var count = 0
    while (count < length) {
        val c = this[count]
        if (c != ' ' && c != '\\t') break
        count++
    }
    return count
}

private fun String.isBlankLine(): Boolean {
    var i = 0
    while (i < length) {
        val c = this[i]
        if (c != ' ' && c != '\\t') return false
        i++
    }
    return true
}

private fun trimBlankEdges(lines: List<String>): List<String> {
    val n = lines.size
    var start = 0
    var end = n
    while (start < end && lines[start].isBlankLine()) start++
    while (end > start && lines[end - 1].isBlankLine()) end--
    val result = mutableListOf<String>()
    var i = start
    while (i < end) {
        result.add(lines[i])
        i++
    }
    return result
}

public fun String.trimIndent(): String {
    val lines = trimBlankEdges(splitIntoLines())
    if (lines.size == 0) return ""
    var minIndent = -1
    for (line in lines) {
        if (!line.isBlankLine()) {
            val cnt = line.leadingWhitespaceCount()
            if (minIndent == -1 || cnt < minIndent) minIndent = cnt
        }
    }
    if (minIndent < 0) minIndent = 0
    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\\n')
        if (line.isBlankLine()) {
            sb.append("")
        } else {
            sb.append(line.kk_drop(minIndent))
        }
        first = false
    }
    return sb.toString()
}

public fun String.trimMargin(marginPrefix: String = "|"): String {
    val lines = trimBlankEdges(splitIntoLines())
    if (lines.size == 0) return ""
    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\\n')
        var i = 0
        while (i < line.length && (line[i] == ' ' || line[i] == '\\t')) i++
        val trimmedLeading = line.kk_drop(i)
        if (trimmedLeading.hasPrefix(marginPrefix)) {
            sb.append(trimmedLeading.kk_drop(marginPrefix.length))
        } else {
            sb.append(line)
        }
        first = false
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
            sb.append(line.kk_drop(drop))
        }
        first = false
    }
    return sb.toString()
}

public fun String.prependIndent(indent: String = "    "): String {
    val lines = splitIntoLines()
    if (lines.size == 0) return this
    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\\n')
        sb.append(indent)
        sb.append(line)
        first = false
    }
    return sb.toString()
}

public fun String.replaceIndent(newIndent: String = ""): String {
    val lines = trimBlankEdges(splitIntoLines())
    if (lines.size == 0) return ""
    var minIndent = -1
    for (line in lines) {
        if (!line.isBlankLine()) {
            val cnt = line.leadingWhitespaceCount()
            if (minIndent == -1 || cnt < minIndent) minIndent = cnt
        }
    }
    if (minIndent < 0) minIndent = 0
    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\\n')
        if (line.isBlankLine()) {
            sb.append("")
        } else {
            sb.append(newIndent)
            sb.append(line.kk_drop(minIndent))
        }
        first = false
    }
    return sb.toString()
}

public fun String.replaceIndentByMargin(newIndent: String = "", marginPrefix: String = "|"): String {
    if (marginPrefix.isBlankLine()) {
        throw IllegalArgumentException("marginPrefix must be non-blank string.")
    }
    val lines = trimBlankEdges(splitIntoLines())
    if (lines.size == 0) return ""
    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\\n')
        var i = 0
        while (i < line.length && (line[i] == ' ' || line[i] == '\\t')) i++
        val trimmedLeading = line.kk_drop(i)
        if (trimmedLeading.hasPrefix(marginPrefix)) {
            sb.append(newIndent)
            sb.append(trimmedLeading.kk_drop(marginPrefix.length))
        } else {
            sb.append(line)
        }
        first = false
    }
    return sb.toString()
}
"""

    // MIGRATION-SEQ-003: Sequence collection-conversion HOFs
    // toList / toSet / toMutableList use forEach as the iteration primitive
    // (intercepted by CollectionLiteralLoweringPass to kk_sequence_forEach).
    //
    // Terminal HOFs (first, last, single, count, any, all, none, …) are resolved
    // via synthetic stubs (HeaderHelpers+SyntheticSequenceTerminalStubs.swift) to
    // the C-level kk_sequence_* entry points in RuntimeSequence.swift.  They are
    // NOT included here to avoid scope pollution that would break Sema resolution
    // for List / Collection / Set receivers with the same member names.
    static let kotlinSequencesSource = """
package kotlin.sequences

// MIGRATION-SEQ-003

public fun <T> Sequence<T>.toList(): List<T> {
    val result = mutableListOf<T>()
    for (element in this) { result.add(element) }
    return result
}

public fun <T> Sequence<T>.toMutableList(): MutableList<T> {
    val result = mutableListOf<T>()
    for (element in this) { result.add(element) }
    return result
}

public fun <T> Sequence<T>.toSet(): Set<T> {
    val result = mutableSetOf<T>()
    for (element in this) { result.add(element) }
    return result
}

"""

}
