@file:kotlin.jvm.JvmName("SequencesKt")
package kotlin.sequences

import kotlin.jvm.internal.__jvmSortListWithComparator

private class SelectorComparator<T, R: Comparable<R>>(val selector: (T) -> R?, val descending: Boolean): Comparator<T> {
    override fun compare(a: T, b: T): Int {
        val first = if (descending) selector(b) else selector(a)
        val second = if (descending) selector(a) else selector(b)
        if (first === second) return 0
        if (first == null) return -1
        if (second == null) return 1
        return first.compareTo(second)
    }
}
public fun <T: Comparable<T>> Sequence<T>.sorted(): Sequence<T> {
    val source = this
    return object: Sequence<T> { override fun iterator(): Iterator<T> = source.asIterable().sorted().iterator() }
}
public fun <T: Comparable<T>> Sequence<T>.sortedDescending(): Sequence<T> {
    val source = this
    return object: Sequence<T> { override fun iterator(): Iterator<T> = source.asIterable().sortedDescending().iterator() }
}
public fun <T, R: Comparable<R>> Sequence<T>.sortedBy(selector: (T) -> R?): Sequence<T> {
    val source = this
    return object: Sequence<T> {
        override fun iterator(): Iterator<T> {
            val result = source.toMutableList()
            __jvmSortListWithComparator(result, SelectorComparator(selector, false))
            return result.iterator()
        }
    }
}
public fun <T, R: Comparable<R>> Sequence<T>.sortedByDescending(selector: (T) -> R?): Sequence<T> {
    val source = this
    return object: Sequence<T> {
        override fun iterator(): Iterator<T> {
            val result = source.toMutableList()
            __jvmSortListWithComparator(result, SelectorComparator(selector, true))
            return result.iterator()
        }
    }
}

fun <T> Sequence<T>.sortedWith(comparator: Comparator<in T>): Sequence<T> {
    val source = this
    return object: Sequence<T> {
        override fun iterator(): Iterator<T> {
            val result = source.toMutableList()
            __jvmSortListWithComparator(result, comparator)
            return result.iterator()
        }
    }
}
