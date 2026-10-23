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

public fun Iterable<Double>.maxOrNull(): Double? = null!!
public fun Iterable<Float>.maxOrNull(): Float? = null!!
public fun <T : Comparable<T>> Iterable<T>.maxOrNull(): T? = null!!

public fun Iterable<Double>.minOrNull(): Double? = null!!
public fun Iterable<Float>.minOrNull(): Float? = null!!
public fun <T : Comparable<T>> Iterable<T>.minOrNull(): T? = null!!
