package kotlin.collections

// MIGRATION-COL-006
// List sorting, ordering, and shuffling HOF functions.
// Migration source: Sources/Runtime/RuntimeCollectionHOFMaxMin.swift
//   (kk_list_reversed, kk_list_sorted, kk_list_shuffled),
//   Sources/Runtime/RuntimeCollectionHOF.swift
//   (kk_list_sortedBy, kk_list_sortedByDescending, kk_list_sortedWith,
//    kk_list_shuffled_random)
//
// NOTE: Not yet wired into the compiler pipeline (RF-STDLIB-004+).
// Sema stubs in HeaderHelpers+SyntheticListTransformMembers.swift and
// HeaderHelpers+SyntheticListAggregateMembers.swift (plus fallback lowering in
// CallLowerer+UnresolvedMemberCalls.swift) still dispatch directly to the
// kk_list_* ABI functions. This file is the migration target; wiring (and
// removal of those stubs) happens in RF-STDLIB-004+.
//
// Implementation strategy:
//   - reversed()             — pure Kotlin (index walk)
//   - sortedWith(comparator) — pure Kotlin stable merge sort
//   - sorted / sortedDescending / sortedBy / sortedByDescending
//                            — delegate to sortedWith
//   - shuffled / shuffled(random) — ABI bridge to kk_list_shuffled /
//                                   kk_list_shuffled_random (Fisher-Yates in Swift)

// ─── ABI bridges (shuffled only) ─────────────────────────────────────────────

@Suppress("UNCHECKED_CAST")
private external fun kk_list_shuffled(list: List<*>): List<*>

@Suppress("UNCHECKED_CAST")
private external fun kk_list_shuffled_random(list: List<*>, random: Any?): List<*>

// ─── reversed ────────────────────────────────────────────────────────────────

public fun <T> List<T>.reversed(): List<T> {
    val result = mutableListOf<T>()
    var i = size - 1
    while (i >= 0) {
        result.add(this[i])
        i--
    }
    return result
}

// ─── sortedWith ──────────────────────────────────────────────────────────────
//
// Stable merge sort. Equal-keyed elements preserve their original relative
// order, matching the guarantee of Kotlin stdlib and java.util.Collections.sort.

public fun <T> Iterable<T>.sortedWith(comparator: Comparator<in T>): List<T> {
    val arr = toMutableList()
    listMergeSort(arr, 0, arr.size, comparator)
    return arr
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

// ─── sorted / sortedDescending ────────────────────────────────────────────────

public fun <T : Comparable<T>> Iterable<T>.sorted(): List<T> =
    sortedWith(Comparator { a, b -> a.compareTo(b) })

public fun <T : Comparable<T>> Iterable<T>.sortedDescending(): List<T> =
    sortedWith(Comparator { a, b -> b.compareTo(a) })

// ─── sortedBy / sortedByDescending ───────────────────────────────────────────

public fun <T, R : Comparable<R>> Iterable<T>.sortedBy(selector: (T) -> R): List<T> =
    sortedWith(Comparator { a, b -> selector(a).compareTo(selector(b)) })

public fun <T, R : Comparable<R>> Iterable<T>.sortedByDescending(selector: (T) -> R): List<T> =
    sortedWith(Comparator { a, b -> selector(b).compareTo(selector(a)) })

// ─── shuffled ────────────────────────────────────────────────────────────────

@Suppress("UNCHECKED_CAST")
public fun <T> Iterable<T>.shuffled(): List<T> =
    kk_list_shuffled(toList()) as List<T>

@Suppress("UNCHECKED_CAST")
public fun <T> Iterable<T>.shuffled(random: kotlin.random.Random): List<T> =
    kk_list_shuffled_random(toList(), random) as List<T>
