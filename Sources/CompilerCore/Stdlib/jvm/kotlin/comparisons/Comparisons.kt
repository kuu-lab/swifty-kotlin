@file:kotlin.jvm.JvmName("ComparisonsKt")
package kotlin.comparisons

import kotlin.Comparator

public fun <T : Comparable<*>> compareValues(a: T?, b: T?): Int {
    if (a === b) return 0
    if (a == null) return -1
    if (b == null) return 1
    return (a as Comparable<Any?>).compareTo(b)
}

public fun <T : Comparable<T>> maxOf(a: T, b: T): T =
    if (compareValues(a, b) >= 0) a else b

public fun <T : Comparable<T>> maxOf(a: T, b: T, c: T): T =
    maxOf(a, maxOf(b, c))

public fun <T : Comparable<T>> maxOf(a: T, vararg other: T): T {
    var result = a
    var i = 0
    while (i < other.size) {
        result = maxOf(result, other[i])
        i += 1
    }
    return result
}

public fun <T : Comparable<T>> minOf(a: T, b: T): T =
    if (compareValues(a, b) <= 0) a else b

public fun <T : Comparable<T>> minOf(a: T, b: T, c: T): T =
    minOf(minOf(a, b), c)

public fun <T : Comparable<T>> minOf(a: T, vararg other: T): T {
    var result = a
    var i = 0
    while (i < other.size) {
        result = minOf(result, other[i])
        i += 1
    }
    return result
}

public fun <T> maxWith(comparator: Comparator<in T>, a: T, b: T): T =
    if (comparator.compare(a, b) >= 0) a else b

public fun <T> minWith(comparator: Comparator<in T>, a: T, b: T): T =
    if (comparator.compare(a, b) <= 0) a else b

public fun <T> maxOf(a: T, b: T, comparator: Comparator<in T>): T =
    if (comparator.compare(a, b) >= 0) a else b

public fun <T> maxOf(a: T, b: T, c: T, comparator: Comparator<in T>): T =
    maxOf(a, maxOf(b, c, comparator), comparator)

public fun <T> maxOf(a: T, vararg other: T, comparator: Comparator<in T>): T {
    var result = a
    var i = 0
    while (i < other.size) {
        if (comparator.compare(result, other[i]) < 0) result = other[i]
        i += 1
    }
    return result
}

public fun <T> minOf(a: T, b: T, comparator: Comparator<in T>): T =
    if (comparator.compare(a, b) <= 0) a else b

public fun <T> minOf(a: T, b: T, c: T, comparator: Comparator<in T>): T =
    minOf(minOf(a, b, comparator), c, comparator)

public fun <T> minOf(a: T, vararg other: T, comparator: Comparator<in T>): T {
    var result = a
    var i = 0
    while (i < other.size) {
        result = minOf(result, other[i], comparator)
        i += 1
    }
    return result
}

public inline fun maxOf(a: Byte, b: Byte): Byte = if (a >= b) a else b
public inline fun maxOf(a: Byte, b: Byte, c: Byte): Byte = maxOf(a, maxOf(b, c))
public fun maxOf(a: Byte, vararg other: Byte): Byte {
    var result = a
    var i = 0
    while (i < other.size) {
        result = maxOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun minOf(a: Byte, b: Byte): Byte = if (a <= b) a else b
public inline fun minOf(a: Byte, b: Byte, c: Byte): Byte = minOf(minOf(a, b), c)
public fun minOf(a: Byte, vararg other: Byte): Byte {
    var result = a
    var i = 0
    while (i < other.size) {
        result = minOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun maxOf(a: Short, b: Short): Short = if (a >= b) a else b
public inline fun maxOf(a: Short, b: Short, c: Short): Short = maxOf(a, maxOf(b, c))
public fun maxOf(a: Short, vararg other: Short): Short {
    var result = a
    var i = 0
    while (i < other.size) {
        result = maxOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun minOf(a: Short, b: Short): Short = if (a <= b) a else b
public inline fun minOf(a: Short, b: Short, c: Short): Short = minOf(minOf(a, b), c)
public fun minOf(a: Short, vararg other: Short): Short {
    var result = a
    var i = 0
    while (i < other.size) {
        result = minOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun maxOf(a: Int, b: Int): Int = if (a >= b) a else b
public inline fun maxOf(a: Int, b: Int, c: Int): Int = maxOf(maxOf(a, b), c)
public fun maxOf(a: Int, vararg other: Int): Int {
    var result = a
    var i = 0
    while (i < other.size) {
        result = maxOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun minOf(a: Int, b: Int): Int = if (a <= b) a else b
public inline fun minOf(a: Int, b: Int, c: Int): Int = minOf(minOf(a, b), c)
public fun minOf(a: Int, vararg other: Int): Int {
    var result = a
    var i = 0
    while (i < other.size) {
        result = minOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun maxOf(a: Long, b: Long): Long = if (a >= b) a else b
public inline fun maxOf(a: Long, b: Long, c: Long): Long = maxOf(maxOf(a, b), c)
public fun maxOf(a: Long, vararg other: Long): Long {
    var result = a
    var i = 0
    while (i < other.size) {
        result = maxOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun minOf(a: Long, b: Long): Long = if (a <= b) a else b
public inline fun minOf(a: Long, b: Long, c: Long): Long = minOf(minOf(a, b), c)
public fun minOf(a: Long, vararg other: Long): Long {
    var result = a
    var i = 0
    while (i < other.size) {
        result = minOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun maxOf(a: Float, b: Float): Float = java.lang.Math.max(a, b)
public inline fun maxOf(a: Float, b: Float, c: Float): Float = maxOf(maxOf(a, b), c)
public fun maxOf(a: Float, vararg other: Float): Float {
    var result = a
    var i = 0
    while (i < other.size) {
        result = maxOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun minOf(a: Float, b: Float): Float = java.lang.Math.min(a, b)
public inline fun minOf(a: Float, b: Float, c: Float): Float = minOf(minOf(a, b), c)
public fun minOf(a: Float, vararg other: Float): Float {
    var result = a
    var i = 0
    while (i < other.size) {
        result = minOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun maxOf(a: Double, b: Double): Double = java.lang.Math.max(a, b)
public inline fun maxOf(a: Double, b: Double, c: Double): Double = maxOf(maxOf(a, b), c)
public fun maxOf(a: Double, vararg other: Double): Double {
    var result = a
    var i = 0
    while (i < other.size) {
        result = maxOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun minOf(a: Double, b: Double): Double = java.lang.Math.min(a, b)
public inline fun minOf(a: Double, b: Double, c: Double): Double = minOf(minOf(a, b), c)
public fun minOf(a: Double, vararg other: Double): Double {
    var result = a
    var i = 0
    while (i < other.size) {
        result = minOf(result, other[i])
        i += 1
    }
    return result
}
