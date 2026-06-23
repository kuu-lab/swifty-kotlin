/// Kotlin source for stdlib functions that are compiled alongside user code.
///
/// Each file is injected as a virtual source file before the pipeline starts,
/// so these functions go through the full Lex → Parse → Sema → KIR → Codegen
/// pipeline and are available as internal LLVM functions at link time.
enum BundledKotlinStdlib {
    // MIGRATION-COL-005: List search HOFs
    // These Kotlin-source definitions are injected as top-level extension functions.
    // Runtime ABI entry points remain registered as compatibility bridges while
    // member-dispatch lowering migrates incrementally.
    //
    // MIGRATION-COL-008: List 集計 HOF
    // count / any / all / none — currently Sema-unresolved (no synthetic stub), so these
    // extension functions are the first resolved definitions and will be called directly.
    // sumOf / maxByOrNull / minByOrNull — synthetic stubs exist in
    // HeaderHelpers+SyntheticListAggregateMembers.swift (member > extension in resolution
    // priority), so these serve as the migration-target definitions; stub removal and
    // dispatch wiring happen in the follow-up RF-LOWER tasks.
    // maxWith / minWith are omitted here because they call Comparator.compare, which is not
    // yet lowerable to a linkable symbol when bundled functions are codegen'd unconditionally.
    static let kotlinCollectionsSource = """
package kotlin.collections

// MIGRATION-COL-005

public fun <T> List<T>.first(): T {
    if (isEmpty()) throw NoSuchElementException("Collection is empty.")
    return this[0]
}

public fun <T> List<T>.first(predicate: (T) -> Boolean): T {
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    throw NoSuchElementException("Collection contains no element matching the predicate.")
}

public fun <T> List<T>.firstOrNull(): T? {
    if (isEmpty()) return null
    return this[0]
}

public fun <T> List<T>.firstOrNull(predicate: (T) -> Boolean): T? {
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun <T> List<T>.find(predicate: (T) -> Boolean): T? {
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun <T> List<T>.last(): T {
    if (isEmpty()) throw NoSuchElementException("Collection is empty.")
    return this[size - 1]
}

public fun <T> List<T>.last(predicate: (T) -> Boolean): T {
    var i = size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    throw NoSuchElementException("Collection contains no element matching the predicate.")
}

public fun <T> List<T>.lastOrNull(): T? {
    if (isEmpty()) return null
    return this[size - 1]
}

public fun <T> List<T>.lastOrNull(predicate: (T) -> Boolean): T? {
    var i = size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun <T> List<T>.findLast(predicate: (T) -> Boolean): T? {
    var i = size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun <T> List<T>.single(): T {
    val sz = size
    if (sz == 1) return this[0]
    if (sz == 0) throw NoSuchElementException("Collection is empty.")
    throw IllegalArgumentException("Collection has more than one element.")
}

public fun <T> List<T>.single(predicate: (T) -> Boolean): T {
    var matchIndex = -1
    var i = 0
    val sz = size
    while (i < sz) {
        if (predicate(this[i])) {
            if (matchIndex >= 0) {
                throw IllegalArgumentException("Collection contains more than one matching element.")
            }
            matchIndex = i
        }
        i++
    }
    if (matchIndex >= 0) return this[matchIndex]
    throw NoSuchElementException("Collection contains no element matching the predicate.")
}

public fun <T> List<T>.singleOrNull(): T? {
    if (size == 1) return this[0]
    return null
}

public fun <T> List<T>.singleOrNull(predicate: (T) -> Boolean): T? {
    var matchIndex = -1
    var i = 0
    val sz = size
    while (i < sz) {
        if (predicate(this[i])) {
            if (matchIndex >= 0) return null
            matchIndex = i
        }
        i++
    }
    if (matchIndex >= 0) return this[matchIndex]
    return null
}

public fun <T> List<T>.indexOf(element: T): Int {
    var i = 0
    val sz = size
    while (i < sz) {
        if (this[i] == element) return i
        i++
    }
    return -1
}

public fun <T> List<T>.indexOfFirst(predicate: (T) -> Boolean): Int {
    var i = 0
    val sz = size
    while (i < sz) {
        if (predicate(this[i])) return i
        i++
    }
    return -1
}

public fun <T> List<T>.indexOfLast(predicate: (T) -> Boolean): Int {
    var i = size - 1
    while (i >= 0) {
        if (predicate(this[i])) return i
        i--
    }
    return -1
}

// MIGRATION-COL-008

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
    if (isEmpty()) return null
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
    if (isEmpty()) return null
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

// MIGRATION-TEXT-005: String case conversion and locale wrappers

public fun String.lowercase(): String {
    if (isEmpty()) return this
    val sb = StringBuilder()
    var i = 0
    while (i < length) {
        sb.append(this[i].lowercase())
        i += 1
    }
    return sb.toString()
}

public fun String.uppercase(): String {
    if (isEmpty()) return this
    val sb = StringBuilder()
    var i = 0
    while (i < length) {
        sb.append(this[i].uppercase())
        i += 1
    }
    return sb.toString()
}

public fun String.capitalize(): String {
    if (isEmpty()) return this
    val sb = StringBuilder()
    sb.append(this[0].uppercase())
    var i = 1
    while (i < length) {
        sb.append(this[i])
        i += 1
    }
    return sb.toString()
}

public fun String.replaceFirstChar(transform: (Char) -> Char): String {
    if (isEmpty()) return this
    val sb = StringBuilder()
    sb.append(transform(this[0]))
    var i = 1
    while (i < length) {
        sb.append(this[i])
        i += 1
    }
    return sb.toString()
}

public fun String.lowercase(locale: java.util.Locale): String =
    this.__kk_lowercase_locale(locale)

public fun String.uppercase(locale: java.util.Locale): String =
    this.__kk_uppercase_locale(locale)


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

// MIGRATION-TEXT-006: String indent and format functions

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
    var sb = StringBuilder()
    var i = 0
    while (i < length) {
        val c = this[i]
        if (c == '\\r') {
            result.add(sb.toString())
            sb = StringBuilder()
            if (i + 1 < length && this[i + 1] == '\\n') {
                i++
            }
        } else if (c == '\\n') {
            result.add(sb.toString())
            sb = StringBuilder()
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
    if (lines.isEmpty()) return ""
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
    if (lines.isEmpty()) return ""
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

public fun String.prependIndent(indent: String = "    "): String {
    val lines = splitIntoLines()
    if (lines.isEmpty()) return this
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
    if (lines.isEmpty()) return ""
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
    if (lines.isEmpty()) return ""
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
}
