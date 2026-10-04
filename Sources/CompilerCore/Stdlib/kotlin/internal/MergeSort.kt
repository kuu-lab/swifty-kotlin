package kotlin.internal

import kotlin.comparisons.minOf

// Shared stable merge sort backing the source-backed `sorted*` HOFs in
// kotlin.collections.SetHOF and kotlin.sequences.SequenceSortingHOF.
// Runs in O(n log n) instead of the previous O(n^2) insertion sorts;
// elements that compare equal under [comparator] keep their original
// relative order, matching the Kotlin `sorted*` contract.

/**
 * Sorts this list in place with a stable bottom-up merge sort, taking the
 * left (earlier) element first when both sides compare equal.
 */
internal fun <T> MutableList<T>.mergeSortWith(comparator: Comparator<in T>) {
    val n = size
    if (n < 2) return
    val scratch = toMutableList()
    var from = scratch
    var into = this
    var width = 1
    while (width < n) {
        var left = 0
        while (left < n) {
            val mid = minOf(left + width, n)
            val right = minOf(mid + width, n)
            var i = left
            var j = mid
            var k = left
            while (k < right) {
                if (i >= mid) {
                    into[k] = from[j]
                    j += 1
                } else if (j >= right) {
                    into[k] = from[i]
                    i += 1
                } else if (comparator.compare(from[j], from[i]) < 0) {
                    into[k] = from[j]
                    j += 1
                } else {
                    into[k] = from[i]
                    i += 1
                }
                k += 1
            }
            left = right
        }
        val swap = from
        from = into
        into = swap
        width *= 2
    }
    if (from !== this) {
        var index = 0
        while (index < n) {
            this[index] = from[index]
            index += 1
        }
    }
}
