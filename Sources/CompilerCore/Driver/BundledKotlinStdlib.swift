/// Residual bundled Kotlin source for stdlib functions not yet migrated to
/// standalone `.kt` files under `Sources/CompilerCore/Stdlib/`.
///
/// As functions are migrated to `.kt` files (auto-discovered by
/// `LoadSourcesPhase.injectBundledStdlib`), remove them from here.
enum BundledKotlinStdlib {
    // count / any / all / none / sumOf / maxByOrNull / minByOrNull are not yet
    // in standalone .kt files. The remaining collection HOFs (search, aggregate,
    // sorting, set) have been migrated to ListSearchHOF.kt, ListAggregateHOF.kt,
    // ListSortingHOF.kt, and SetHOF.kt respectively.
    static let kotlinCollectionsSource = """
package kotlin.collections

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
