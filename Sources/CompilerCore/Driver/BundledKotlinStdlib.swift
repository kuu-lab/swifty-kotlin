/// Kotlin source for stdlib functions that are compiled alongside user code.
///
/// Each file is injected as a virtual source file before the pipeline starts,
/// so these functions go through the full Lex → Parse → Sema → KIR → Codegen
/// pipeline and are available as internal LLVM functions at link time.
enum BundledKotlinStdlib {
    // MIGRATION-COL-008: List 集計 HOF
    // count / any / all / none — currently Sema-unresolved (no synthetic stub), so these
    // extension functions are the first resolved definitions and will be called directly.
    // sumOf / maxByOrNull / minByOrNull — synthetic stubs exist in
    // HeaderHelpers+SyntheticListAggregateMembers.swift (member > extension in resolution
    // priority), so these serve as the migration-target definitions; stub removal and
    // dispatch wiring happen in the follow-up RF-LOWER tasks.
    // maxWith / minWith are omitted here because they call Comparator.compare, which is not
    // yet lowerable to a linkable symbol when bundled functions are codegen'd unconditionally.
    
    // MIGRATION-COL-006: List ソート・比較 HOF
    // reversed / sorted / sortedDescending / sortedBy / sortedByDescending / sortedWith
    // — pure Kotlin implementations (no ABI bridges needed except for shuffled).
    // shuffled / shuffled(random) — ABI bridges to kk_list_shuffled / kk_list_shuffled_random.
    // NOTE: Not yet wired into the compiler pipeline (RF-STDLIB-004+). Sema stubs in
    // HeaderHelpers+SyntheticListTransformMembers.swift and
    // HeaderHelpers+SyntheticListAggregateMembers.swift still dispatch directly to the
    // kk_list_* ABI functions. This is the migration target; wiring happens in RF-STDLIB-004+.
    
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

// MIGRATION-COL-006: List sorting functions

public fun <T> List<T>.reversed(): List<T> {
    val result = mutableListOf<T>()
    var i = size - 1
    while (i >= 0) {
        result.add(this[i])
        i--
    }
    return result
}

private fun <T> listMergeSort(arr: MutableList<T>, from: Int, to: Int, cmp: Comparator<in T>) {
    if (to - from <= 1) return
    val mid = from + (to - from) / 2
    listMergeSort(arr, from, mid, cmp)
    listMergeSort(arr, mid, to, cmp)
    listMerge(arr, from, mid, to, cmp)
}

private fun <T> listMerge(arr: MutableList<T>, from: Int, mid: Int, to: Int, cmp: Comparator<in T>) {
    val left = mutableListOf<T>()
    var i = from
    while (i < mid) { left.add(arr[i]); i++ }
    val right = mutableListOf<T>()
    var j = mid
    while (j < to) { right.add(arr[j]); j++ }

    var l = 0
    var r = 0
    var k = from
    while (l < left.size && r < right.size) {
        if (cmp.compare(left[l], right[r]) <= 0) {
            arr[k] = left[l]; l++
        } else {
            arr[k] = right[r]; r++
        }
        k++
    }
    while (l < left.size) { arr[k] = left[l]; l++; k++ }
    while (r < right.size) { arr[k] = right[r]; r++; k++ }
}

public fun <T> Iterable<T>.sortedWith(comparator: Comparator<in T>): List<T> {
    val arr = toMutableList()
    listMergeSort(arr, 0, arr.size, comparator)
    return arr
}

public fun <T : Comparable<T>> Iterable<T>.sorted(): List<T> =
    sortedWith(Comparator { a, b -> a.compareTo(b) })

public fun <T : Comparable<T>> Iterable<T>.sortedDescending(): List<T> =
    sortedWith(Comparator { a, b -> b.compareTo(a) })

public fun <T, R : Comparable<R>> Iterable<T>.sortedBy(selector: (T) -> R): List<T> =
    sortedWith(Comparator { a, b -> selector(a).compareTo(selector(b)) })

public fun <T, R : Comparable<R>> Iterable<T>.sortedByDescending(selector: (T) -> R): List<T> =
    sortedWith(Comparator { a, b -> selector(b).compareTo(selector(a)) })

// MIGRATION-COL-006: List shuffling functions (ABI bridges)

@Suppress("UNCHECKED_CAST")
private external fun kk_list_shuffled(list: List<*>): List<*>

@Suppress("UNCHECKED_CAST")
private external fun kk_list_shuffled_random(list: List<*>, random: Any?): List<*>

@Suppress("UNCHECKED_CAST")
public fun <T> Iterable<T>.shuffled(): List<T> =
    kk_list_shuffled(toList()) as List<T>

@Suppress("UNCHECKED_CAST")
public fun <T> Iterable<T>.shuffled(random: kotlin.random.Random): List<T> =
    kk_list_shuffled_random(toList(), random) as List<T>
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
}
