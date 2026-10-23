@file:kotlin.jvm.JvmName("CollectionsKt")
package kotlin.collections

import kotlin.Comparator

public fun <T, R> Iterable<T>.maxOfWith(comparator: Comparator<in R>, selector: (T) -> R): R {
    val iterator = this.iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    var result = selector(iterator.next())
    while (iterator.hasNext()) {
        val value = selector(iterator.next())
        if (comparator.compare(value, result) > 0) result = value
    }
    return result
}

public fun <T, R> Iterable<T>.maxOfWithOrNull(comparator: Comparator<in R>, selector: (T) -> R): R? {
    val iterator = this.iterator()
    if (!iterator.hasNext()) return null
    var result = selector(iterator.next())
    while (iterator.hasNext()) {
        val value = selector(iterator.next())
        if (comparator.compare(value, result) > 0) result = value
    }
    return result
}

public fun <T, R> Iterable<T>.minOfWith(comparator: Comparator<in R>, selector: (T) -> R): R {
    val iterator = this.iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    var result = selector(iterator.next())
    while (iterator.hasNext()) {
        val value = selector(iterator.next())
        if (comparator.compare(value, result) < 0) result = value
    }
    return result
}

public fun <T, R> Iterable<T>.minOfWithOrNull(comparator: Comparator<in R>, selector: (T) -> R): R? {
    val iterator = this.iterator()
    if (!iterator.hasNext()) return null
    var result = selector(iterator.next())
    while (iterator.hasNext()) {
        val value = selector(iterator.next())
        if (comparator.compare(value, result) < 0) result = value
    }
    return result
}
