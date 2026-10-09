package kotlin.collections

import kotlin.comparisons.compareValuesBy
import kotlin.comparisons.minOf as comparisonMinOf

// Shared stable sort core for the source-backed stdlib. Every sort entry point
// in ArraySortingHOF.kt, ListSortingHOF.kt and Iterables.kt routes through the
// helpers here: a bottom-up merge sort over one scratch buffer that falls back
// to insertion sort for runs of at most STABLE_SORT_RUN elements. The sort is
// stable, preserving the ordering contract of sortedBy / sortedWith, and runs
// in O(n log n) comparisons instead of the previous O(n^2) hand-written
// insertion/bubble sorts.
//
// The sort bodies call comparator.compare (or the selector / comparison lambda
// parameters) directly. Selector and comparison lambdas are deliberately passed
// through ordinary function parameters rather than stored on helper classes or
// wrapped in SAM conversions: inside bundled sources, both a lambda stored in
// a class property and a lambda literal whose body delegates to another call
// miscompile, dropping the captured reference and exceptions thrown by the
// call.

@PublishedApi
internal const val STABLE_SORT_RUN: Int = 16

// --- Selector / comparison element sort --------------------------------------
//
// These helpers call the selector/comparison lambdas through ordinary function
// parameters. Routing them through Comparator implementations would wrap them
// in an extra function boundary that currently miscompiles inside the bundled
// sources, dropping both the stored lambda reference and thrown exceptions.

@PublishedApi
internal fun <T, R : Comparable<R>> MutableList<T>.stableSortBySelector(
    selector: (T) -> R?,
    descending: Boolean
) {
    val n = this.size
    if (n <= 1) return
    var start = 0
    while (start < n) {
        val end = comparisonMinOf(start + STABLE_SORT_RUN, n)
        var i = start + 1
        while (i < end) {
            val element = this[i]
            var j = i - 1
            if (descending) {
                while (j >= start && compareValuesBy(this[j], element, selector) < 0) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            } else {
                while (j >= start && compareValuesBy(this[j], element, selector) > 0) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            }
            this[j + 1] = element
            i += 1
        }
        start = end
    }
    if (n <= STABLE_SORT_RUN) return
    val scratch = this.toMutableList()
    var src: MutableList<T> = this
    var dst: MutableList<T> = scratch
    var width = STABLE_SORT_RUN
    while (width < n) {
        var i = 0
        while (i < n) {
            val mid = if (i >= n - width) n else i + width
            val end = if (mid >= n - width) n else mid + width
            var a = i
            var b = mid
            var k = i
            if (descending) {
                while (a < mid && b < end) {
                    if (compareValuesBy(src[b], src[a], selector) > 0) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            } else {
                while (a < mid && b < end) {
                    if (compareValuesBy(src[b], src[a], selector) < 0) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            }
            while (a < mid) {
                dst[k] = src[a]
                a += 1
                k += 1
            }
            while (b < end) {
                dst[k] = src[b]
                b += 1
                k += 1
            }
            i = end
        }
        val tmp = src
        src = dst
        dst = tmp
        if (width >= n - width) break
        width += width
    }
    if (src !== this) {
        var i = 0
        while (i < n) {
            this[i] = src[i]
            i += 1
        }
    }
}

@PublishedApi
internal fun <T> MutableList<T>.stableSortByComparison(comparison: (T, T) -> Int) {
    val n = this.size
    if (n <= 1) return
    var start = 0
    while (start < n) {
        val end = comparisonMinOf(start + STABLE_SORT_RUN, n)
        var i = start + 1
        while (i < end) {
            val element = this[i]
            var j = i - 1
            while (j >= start && comparison(this[j], element) > 0) {
                this[j + 1] = this[j]
                j -= 1
            }
            this[j + 1] = element
            i += 1
        }
        start = end
    }
    if (n <= STABLE_SORT_RUN) return
    val scratch = this.toMutableList()
    var src: MutableList<T> = this
    var dst: MutableList<T> = scratch
    var width = STABLE_SORT_RUN
    while (width < n) {
        var i = 0
        while (i < n) {
            val mid = if (i >= n - width) n else i + width
            val end = if (mid >= n - width) n else mid + width
            var a = i
            var b = mid
            var k = i
            while (a < mid && b < end) {
                if (comparison(src[b], src[a]) < 0) {
                    dst[k] = src[b]
                    b += 1
                } else {
                    dst[k] = src[a]
                    a += 1
                }
                k += 1
            }
            while (a < mid) {
                dst[k] = src[a]
                a += 1
                k += 1
            }
            while (b < end) {
                dst[k] = src[b]
                b += 1
                k += 1
            }
            i = end
        }
        val tmp = src
        src = dst
        dst = tmp
        if (width >= n - width) break
        width += width
    }
    if (src !== this) {
        var i = 0
        while (i < n) {
            this[i] = src[i]
            i += 1
        }
    }
}

// --- Generic element sort ----------------------------------------------------

@PublishedApi
internal fun <T> Array<T>.stableSortWith(comparator: Comparator<T>) {
    val n = this.size
    if (n <= 1) return
    var start = 0
    while (start < n) {
        val end = comparisonMinOf(start + STABLE_SORT_RUN, n)
        var i = start + 1
        while (i < end) {
            val element = this[i]
            var j = i - 1
            while (j >= start && comparator.compare(this[j], element) > 0) {
                this[j + 1] = this[j]
                j -= 1
            }
            this[j + 1] = element
            i += 1
        }
        start = end
    }
    if (n <= STABLE_SORT_RUN) return
    val scratch = this.copyOf()
    var src: Array<T> = this
    var dst: Array<T> = scratch
    var width = STABLE_SORT_RUN
    while (width < n) {
        var i = 0
        while (i < n) {
            // `i >= n - width` etc. keep the bounds overflow-free for large n.
            val mid = if (i >= n - width) n else i + width
            val end = if (mid >= n - width) n else mid + width
            var a = i
            var b = mid
            var k = i
            while (a < mid && b < end) {
                // Left wins ties to keep the sort stable.
                if (comparator.compare(src[b], src[a]) < 0) {
                    dst[k] = src[b]
                    b += 1
                } else {
                    dst[k] = src[a]
                    a += 1
                }
                k += 1
            }
            while (a < mid) {
                dst[k] = src[a]
                a += 1
                k += 1
            }
            while (b < end) {
                dst[k] = src[b]
                b += 1
                k += 1
            }
            i = end
        }
        val tmp = src
        src = dst
        dst = tmp
        if (width >= n - width) break
        width += width
    }
    if (src !== this) {
        var i = 0
        while (i < n) {
            this[i] = src[i]
            i += 1
        }
    }
}

@PublishedApi
internal fun <T> MutableList<T>.stableSortWith(comparator: Comparator<T>) {
    val n = this.size
    if (n <= 1) return
    var start = 0
    while (start < n) {
        val end = comparisonMinOf(start + STABLE_SORT_RUN, n)
        var i = start + 1
        while (i < end) {
            val element = this[i]
            var j = i - 1
            while (j >= start && comparator.compare(this[j], element) > 0) {
                this[j + 1] = this[j]
                j -= 1
            }
            this[j + 1] = element
            i += 1
        }
        start = end
    }
    if (n <= STABLE_SORT_RUN) return
    val scratch = this.toMutableList()
    var src: MutableList<T> = this
    var dst: MutableList<T> = scratch
    var width = STABLE_SORT_RUN
    while (width < n) {
        var i = 0
        while (i < n) {
            val mid = if (i >= n - width) n else i + width
            val end = if (mid >= n - width) n else mid + width
            var a = i
            var b = mid
            var k = i
            while (a < mid && b < end) {
                if (comparator.compare(src[b], src[a]) < 0) {
                    dst[k] = src[b]
                    b += 1
                } else {
                    dst[k] = src[a]
                    a += 1
                }
                k += 1
            }
            while (a < mid) {
                dst[k] = src[a]
                a += 1
                k += 1
            }
            while (b < end) {
                dst[k] = src[b]
                b += 1
                k += 1
            }
            i = end
        }
        val tmp = src
        src = dst
        dst = tmp
        if (width >= n - width) break
        width += width
    }
    if (src !== this) {
        var i = 0
        while (i < n) {
            this[i] = src[i]
            i += 1
        }
    }
}


// --- Primitive array sort ----------------------------------------------------
// Stability is unobservable for primitive elements, but the same bottom-up
// merge structure is kept so every array type shares the O(n log n) shape.
// Primitive helpers sort directly on element comparisons, so no comparator
// adapter is needed.

internal fun IntArray.stableSortImpl(descending: Boolean) {
    val n = this.size
    if (n <= 1) return
    var start = 0
    while (start < n) {
        val end = comparisonMinOf(start + STABLE_SORT_RUN, n)
        var i = start + 1
        while (i < end) {
            val element = this[i]
            var j = i - 1
            if (descending) {
                while (j >= start && this[j] < element) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            } else {
                while (j >= start && this[j] > element) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            }
            this[j + 1] = element
            i += 1
        }
        start = end
    }
    if (n <= STABLE_SORT_RUN) return
    val scratch = this.copyOf()
    var src: IntArray = this
    var dst: IntArray = scratch
    var width = STABLE_SORT_RUN
    while (width < n) {
        var i = 0
        while (i < n) {
            val mid = if (i >= n - width) n else i + width
            val end = if (mid >= n - width) n else mid + width
            var a = i
            var b = mid
            var k = i
            if (descending) {
                while (a < mid && b < end) {
                    if (src[b] > src[a]) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            } else {
                while (a < mid && b < end) {
                    if (src[b] < src[a]) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            }
            while (a < mid) {
                dst[k] = src[a]
                a += 1
                k += 1
            }
            while (b < end) {
                dst[k] = src[b]
                b += 1
                k += 1
            }
            i = end
        }
        val tmp = src
        src = dst
        dst = tmp
        if (width >= n - width) break
        width += width
    }
    if (src !== this) {
        var i = 0
        while (i < n) {
            this[i] = src[i]
            i += 1
        }
    }
}

internal fun LongArray.stableSortImpl(descending: Boolean) {
    val n = this.size
    if (n <= 1) return
    var start = 0
    while (start < n) {
        val end = comparisonMinOf(start + STABLE_SORT_RUN, n)
        var i = start + 1
        while (i < end) {
            val element = this[i]
            var j = i - 1
            if (descending) {
                while (j >= start && this[j] < element) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            } else {
                while (j >= start && this[j] > element) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            }
            this[j + 1] = element
            i += 1
        }
        start = end
    }
    if (n <= STABLE_SORT_RUN) return
    val scratch = this.copyOf()
    var src: LongArray = this
    var dst: LongArray = scratch
    var width = STABLE_SORT_RUN
    while (width < n) {
        var i = 0
        while (i < n) {
            val mid = if (i >= n - width) n else i + width
            val end = if (mid >= n - width) n else mid + width
            var a = i
            var b = mid
            var k = i
            if (descending) {
                while (a < mid && b < end) {
                    if (src[b] > src[a]) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            } else {
                while (a < mid && b < end) {
                    if (src[b] < src[a]) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            }
            while (a < mid) {
                dst[k] = src[a]
                a += 1
                k += 1
            }
            while (b < end) {
                dst[k] = src[b]
                b += 1
                k += 1
            }
            i = end
        }
        val tmp = src
        src = dst
        dst = tmp
        if (width >= n - width) break
        width += width
    }
    if (src !== this) {
        var i = 0
        while (i < n) {
            this[i] = src[i]
            i += 1
        }
    }
}

internal fun ByteArray.stableSortImpl(descending: Boolean) {
    val n = this.size
    if (n <= 1) return
    var start = 0
    while (start < n) {
        val end = comparisonMinOf(start + STABLE_SORT_RUN, n)
        var i = start + 1
        while (i < end) {
            val element = this[i]
            var j = i - 1
            if (descending) {
                while (j >= start && this[j] < element) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            } else {
                while (j >= start && this[j] > element) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            }
            this[j + 1] = element
            i += 1
        }
        start = end
    }
    if (n <= STABLE_SORT_RUN) return
    val scratch = this.copyOf()
    var src: ByteArray = this
    var dst: ByteArray = scratch
    var width = STABLE_SORT_RUN
    while (width < n) {
        var i = 0
        while (i < n) {
            val mid = if (i >= n - width) n else i + width
            val end = if (mid >= n - width) n else mid + width
            var a = i
            var b = mid
            var k = i
            if (descending) {
                while (a < mid && b < end) {
                    if (src[b] > src[a]) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            } else {
                while (a < mid && b < end) {
                    if (src[b] < src[a]) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            }
            while (a < mid) {
                dst[k] = src[a]
                a += 1
                k += 1
            }
            while (b < end) {
                dst[k] = src[b]
                b += 1
                k += 1
            }
            i = end
        }
        val tmp = src
        src = dst
        dst = tmp
        if (width >= n - width) break
        width += width
    }
    if (src !== this) {
        var i = 0
        while (i < n) {
            this[i] = src[i]
            i += 1
        }
    }
}

internal fun ShortArray.stableSortImpl(descending: Boolean) {
    val n = this.size
    if (n <= 1) return
    var start = 0
    while (start < n) {
        val end = comparisonMinOf(start + STABLE_SORT_RUN, n)
        var i = start + 1
        while (i < end) {
            val element = this[i]
            var j = i - 1
            if (descending) {
                while (j >= start && this[j] < element) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            } else {
                while (j >= start && this[j] > element) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            }
            this[j + 1] = element
            i += 1
        }
        start = end
    }
    if (n <= STABLE_SORT_RUN) return
    val scratch = this.copyOf()
    var src: ShortArray = this
    var dst: ShortArray = scratch
    var width = STABLE_SORT_RUN
    while (width < n) {
        var i = 0
        while (i < n) {
            val mid = if (i >= n - width) n else i + width
            val end = if (mid >= n - width) n else mid + width
            var a = i
            var b = mid
            var k = i
            if (descending) {
                while (a < mid && b < end) {
                    if (src[b] > src[a]) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            } else {
                while (a < mid && b < end) {
                    if (src[b] < src[a]) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            }
            while (a < mid) {
                dst[k] = src[a]
                a += 1
                k += 1
            }
            while (b < end) {
                dst[k] = src[b]
                b += 1
                k += 1
            }
            i = end
        }
        val tmp = src
        src = dst
        dst = tmp
        if (width >= n - width) break
        width += width
    }
    if (src !== this) {
        var i = 0
        while (i < n) {
            this[i] = src[i]
            i += 1
        }
    }
}

internal fun CharArray.stableSortImpl(descending: Boolean) {
    val n = this.size
    if (n <= 1) return
    var start = 0
    while (start < n) {
        val end = comparisonMinOf(start + STABLE_SORT_RUN, n)
        var i = start + 1
        while (i < end) {
            val element = this[i]
            var j = i - 1
            if (descending) {
                while (j >= start && this[j] < element) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            } else {
                while (j >= start && this[j] > element) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            }
            this[j + 1] = element
            i += 1
        }
        start = end
    }
    if (n <= STABLE_SORT_RUN) return
    val scratch = this.copyOf()
    var src: CharArray = this
    var dst: CharArray = scratch
    var width = STABLE_SORT_RUN
    while (width < n) {
        var i = 0
        while (i < n) {
            val mid = if (i >= n - width) n else i + width
            val end = if (mid >= n - width) n else mid + width
            var a = i
            var b = mid
            var k = i
            if (descending) {
                while (a < mid && b < end) {
                    if (src[b] > src[a]) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            } else {
                while (a < mid && b < end) {
                    if (src[b] < src[a]) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            }
            while (a < mid) {
                dst[k] = src[a]
                a += 1
                k += 1
            }
            while (b < end) {
                dst[k] = src[b]
                b += 1
                k += 1
            }
            i = end
        }
        val tmp = src
        src = dst
        dst = tmp
        if (width >= n - width) break
        width += width
    }
    if (src !== this) {
        var i = 0
        while (i < n) {
            this[i] = src[i]
            i += 1
        }
    }
}

internal fun DoubleArray.stableSortImpl(descending: Boolean) {
    val n = this.size
    if (n <= 1) return
    var start = 0
    while (start < n) {
        val end = comparisonMinOf(start + STABLE_SORT_RUN, n)
        var i = start + 1
        while (i < end) {
            val element = this[i]
            var j = i - 1
            if (descending) {
                while (j >= start && this[j].compareTo(element) < 0) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            } else {
                while (j >= start && this[j].compareTo(element) > 0) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            }
            this[j + 1] = element
            i += 1
        }
        start = end
    }
    if (n <= STABLE_SORT_RUN) return
    val scratch = this.copyOf()
    var src: DoubleArray = this
    var dst: DoubleArray = scratch
    var width = STABLE_SORT_RUN
    while (width < n) {
        var i = 0
        while (i < n) {
            val mid = if (i >= n - width) n else i + width
            val end = if (mid >= n - width) n else mid + width
            var a = i
            var b = mid
            var k = i
            if (descending) {
                while (a < mid && b < end) {
                    if (src[b].compareTo(src[a]) > 0) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            } else {
                while (a < mid && b < end) {
                    if (src[b].compareTo(src[a]) < 0) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            }
            while (a < mid) {
                dst[k] = src[a]
                a += 1
                k += 1
            }
            while (b < end) {
                dst[k] = src[b]
                b += 1
                k += 1
            }
            i = end
        }
        val tmp = src
        src = dst
        dst = tmp
        if (width >= n - width) break
        width += width
    }
    if (src !== this) {
        var i = 0
        while (i < n) {
            this[i] = src[i]
            i += 1
        }
    }
}

internal fun FloatArray.stableSortImpl(descending: Boolean) {
    val n = this.size
    if (n <= 1) return
    var start = 0
    while (start < n) {
        val end = comparisonMinOf(start + STABLE_SORT_RUN, n)
        var i = start + 1
        while (i < end) {
            val element = this[i]
            var j = i - 1
            if (descending) {
                while (j >= start && this[j].compareTo(element) < 0) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            } else {
                while (j >= start && this[j].compareTo(element) > 0) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            }
            this[j + 1] = element
            i += 1
        }
        start = end
    }
    if (n <= STABLE_SORT_RUN) return
    val scratch = this.copyOf()
    var src: FloatArray = this
    var dst: FloatArray = scratch
    var width = STABLE_SORT_RUN
    while (width < n) {
        var i = 0
        while (i < n) {
            val mid = if (i >= n - width) n else i + width
            val end = if (mid >= n - width) n else mid + width
            var a = i
            var b = mid
            var k = i
            if (descending) {
                while (a < mid && b < end) {
                    if (src[b].compareTo(src[a]) > 0) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            } else {
                while (a < mid && b < end) {
                    if (src[b].compareTo(src[a]) < 0) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            }
            while (a < mid) {
                dst[k] = src[a]
                a += 1
                k += 1
            }
            while (b < end) {
                dst[k] = src[b]
                b += 1
                k += 1
            }
            i = end
        }
        val tmp = src
        src = dst
        dst = tmp
        if (width >= n - width) break
        width += width
    }
    if (src !== this) {
        var i = 0
        while (i < n) {
            this[i] = src[i]
            i += 1
        }
    }
}

internal fun UByteArray.stableSortImpl(descending: Boolean) {
    val n = this.size
    if (n <= 1) return
    var start = 0
    while (start < n) {
        val end = comparisonMinOf(start + STABLE_SORT_RUN, n)
        var i = start + 1
        while (i < end) {
            val element = this[i]
            var j = i - 1
            if (descending) {
                while (j >= start && this[j] < element) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            } else {
                while (j >= start && this[j] > element) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            }
            this[j + 1] = element
            i += 1
        }
        start = end
    }
    if (n <= STABLE_SORT_RUN) return
    val scratch = this.copyOf()
    var src: UByteArray = this
    var dst: UByteArray = scratch
    var width = STABLE_SORT_RUN
    while (width < n) {
        var i = 0
        while (i < n) {
            val mid = if (i >= n - width) n else i + width
            val end = if (mid >= n - width) n else mid + width
            var a = i
            var b = mid
            var k = i
            if (descending) {
                while (a < mid && b < end) {
                    if (src[b] > src[a]) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            } else {
                while (a < mid && b < end) {
                    if (src[b] < src[a]) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            }
            while (a < mid) {
                dst[k] = src[a]
                a += 1
                k += 1
            }
            while (b < end) {
                dst[k] = src[b]
                b += 1
                k += 1
            }
            i = end
        }
        val tmp = src
        src = dst
        dst = tmp
        if (width >= n - width) break
        width += width
    }
    if (src !== this) {
        var i = 0
        while (i < n) {
            this[i] = src[i]
            i += 1
        }
    }
}

internal fun UShortArray.stableSortImpl(descending: Boolean) {
    val n = this.size
    if (n <= 1) return
    var start = 0
    while (start < n) {
        val end = comparisonMinOf(start + STABLE_SORT_RUN, n)
        var i = start + 1
        while (i < end) {
            val element = this[i]
            var j = i - 1
            if (descending) {
                while (j >= start && this[j] < element) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            } else {
                while (j >= start && this[j] > element) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            }
            this[j + 1] = element
            i += 1
        }
        start = end
    }
    if (n <= STABLE_SORT_RUN) return
    val scratch = this.copyOf()
    var src: UShortArray = this
    var dst: UShortArray = scratch
    var width = STABLE_SORT_RUN
    while (width < n) {
        var i = 0
        while (i < n) {
            val mid = if (i >= n - width) n else i + width
            val end = if (mid >= n - width) n else mid + width
            var a = i
            var b = mid
            var k = i
            if (descending) {
                while (a < mid && b < end) {
                    if (src[b] > src[a]) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            } else {
                while (a < mid && b < end) {
                    if (src[b] < src[a]) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            }
            while (a < mid) {
                dst[k] = src[a]
                a += 1
                k += 1
            }
            while (b < end) {
                dst[k] = src[b]
                b += 1
                k += 1
            }
            i = end
        }
        val tmp = src
        src = dst
        dst = tmp
        if (width >= n - width) break
        width += width
    }
    if (src !== this) {
        var i = 0
        while (i < n) {
            this[i] = src[i]
            i += 1
        }
    }
}

internal fun UIntArray.stableSortImpl(descending: Boolean) {
    val n = this.size
    if (n <= 1) return
    var start = 0
    while (start < n) {
        val end = comparisonMinOf(start + STABLE_SORT_RUN, n)
        var i = start + 1
        while (i < end) {
            val element = this[i]
            var j = i - 1
            if (descending) {
                while (j >= start && this[j] < element) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            } else {
                while (j >= start && this[j] > element) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            }
            this[j + 1] = element
            i += 1
        }
        start = end
    }
    if (n <= STABLE_SORT_RUN) return
    val scratch = this.copyOf()
    var src: UIntArray = this
    var dst: UIntArray = scratch
    var width = STABLE_SORT_RUN
    while (width < n) {
        var i = 0
        while (i < n) {
            val mid = if (i >= n - width) n else i + width
            val end = if (mid >= n - width) n else mid + width
            var a = i
            var b = mid
            var k = i
            if (descending) {
                while (a < mid && b < end) {
                    if (src[b] > src[a]) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            } else {
                while (a < mid && b < end) {
                    if (src[b] < src[a]) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            }
            while (a < mid) {
                dst[k] = src[a]
                a += 1
                k += 1
            }
            while (b < end) {
                dst[k] = src[b]
                b += 1
                k += 1
            }
            i = end
        }
        val tmp = src
        src = dst
        dst = tmp
        if (width >= n - width) break
        width += width
    }
    if (src !== this) {
        var i = 0
        while (i < n) {
            this[i] = src[i]
            i += 1
        }
    }
}

internal fun ULongArray.stableSortImpl(descending: Boolean) {
    val n = this.size
    if (n <= 1) return
    var start = 0
    while (start < n) {
        val end = comparisonMinOf(start + STABLE_SORT_RUN, n)
        var i = start + 1
        while (i < end) {
            val element = this[i]
            var j = i - 1
            if (descending) {
                while (j >= start && this[j] < element) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            } else {
                while (j >= start && this[j] > element) {
                    this[j + 1] = this[j]
                    j -= 1
                }
            }
            this[j + 1] = element
            i += 1
        }
        start = end
    }
    if (n <= STABLE_SORT_RUN) return
    val scratch = this.copyOf()
    var src: ULongArray = this
    var dst: ULongArray = scratch
    var width = STABLE_SORT_RUN
    while (width < n) {
        var i = 0
        while (i < n) {
            val mid = if (i >= n - width) n else i + width
            val end = if (mid >= n - width) n else mid + width
            var a = i
            var b = mid
            var k = i
            if (descending) {
                while (a < mid && b < end) {
                    if (src[b] > src[a]) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            } else {
                while (a < mid && b < end) {
                    if (src[b] < src[a]) {
                        dst[k] = src[b]
                        b += 1
                    } else {
                        dst[k] = src[a]
                        a += 1
                    }
                    k += 1
                }
            }
            while (a < mid) {
                dst[k] = src[a]
                a += 1
                k += 1
            }
            while (b < end) {
                dst[k] = src[b]
                b += 1
                k += 1
            }
            i = end
        }
        val tmp = src
        src = dst
        dst = tmp
        if (width >= n - width) break
        width += width
    }
    if (src !== this) {
        var i = 0
        while (i < n) {
            this[i] = src[i]
            i += 1
        }
    }
}
