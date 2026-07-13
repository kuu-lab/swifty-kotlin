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
    static let kotlinTextSource = ""

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
