@file:kotlin.jvm.JvmName("CollectionsKt")
package kotlin.collections

public inline fun <T> Iterable<T>.count(predicate: (T) -> Boolean): Int {
    var count = 0
    for (element in this) {
        if (predicate(element)) {
            count += 1
            if (count < 0) throw ArithmeticException("Count overflow has happened.")
        }
    }
    return count
}

public fun Iterable<Double>.maxOrNull(): Double? {
    val iterator = iterator()
    if (!iterator.hasNext()) return null
    var max = iterator.next()
    while (iterator.hasNext()) max = kotlin.math.max(max, iterator.next())
    return max
}

public fun Iterable<Float>.maxOrNull(): Float? {
    val iterator = iterator()
    if (!iterator.hasNext()) return null
    var max = iterator.next()
    while (iterator.hasNext()) max = kotlin.math.max(max, iterator.next())
    return max
}

public fun <T : Comparable<T>> Iterable<T>.maxOrNull(): T? {
    val iterator = iterator()
    if (!iterator.hasNext()) return null
    var max = iterator.next()
    while (iterator.hasNext()) {
        val value = iterator.next()
        if (max < value) max = value
    }
    return max
}

public fun Iterable<Double>.minOrNull(): Double? {
    val iterator = iterator()
    if (!iterator.hasNext()) return null
    var min = iterator.next()
    while (iterator.hasNext()) min = kotlin.math.min(min, iterator.next())
    return min
}

public fun Iterable<Float>.minOrNull(): Float? {
    val iterator = iterator()
    if (!iterator.hasNext()) return null
    var min = iterator.next()
    while (iterator.hasNext()) min = kotlin.math.min(min, iterator.next())
    return min
}

public fun <T : Comparable<T>> Iterable<T>.minOrNull(): T? {
    val iterator = iterator()
    if (!iterator.hasNext()) return null
    var min = iterator.next()
    while (iterator.hasNext()) {
        val value = iterator.next()
        if (min > value) min = value
    }
    return min
}
