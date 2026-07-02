package kotlin.comparisons

// MIGRATION-COMP-002
// maxOf / minOf overloads migrated to Kotlin source.
//
// NOTE: CallLowerer still recognizes this source-backed API surface and lowers
// primitive, comparable, comparator, and vararg calls inline. Float/Double
// overloads delegate to the existing runtime helpers so NaN propagation and
// signed-zero ordering stay aligned with Kotlin semantics.

private external fun kk_max_float(a: Float, b: Float): Float
private external fun kk_min_float(a: Float, b: Float): Float
private external fun kk_max_double(a: Double, b: Double): Double
private external fun kk_min_double(a: Double, b: Double): Double

// Comparable overloads

public inline fun <T : Comparable<T>> maxOf(a: T, b: T): T =
    if (a.compareTo(b) >= 0) a else b

public inline fun <T : Comparable<T>> maxOf(a: T, b: T, c: T): T =
    maxOf(maxOf(a, b), c)

public inline fun <T : Comparable<T>> maxOf(vararg values: T): T {
    if (values.size == 0) throw IllegalArgumentException("Failed requirement.")
    var result = values[0]
    var i = 1
    while (i < values.size) {
        result = maxOf(result, values[i])
        i += 1
    }
    return result
}

public inline fun <T : Comparable<T>> minOf(a: T, b: T): T =
    if (a.compareTo(b) <= 0) a else b

public inline fun <T : Comparable<T>> minOf(a: T, b: T, c: T): T =
    minOf(minOf(a, b), c)

public inline fun <T : Comparable<T>> minOf(vararg values: T): T {
    if (values.size == 0) throw IllegalArgumentException("Failed requirement.")
    var result = values[0]
    var i = 1
    while (i < values.size) {
        result = minOf(result, values[i])
        i += 1
    }
    return result
}

// Comparator overloads

public inline fun <T> maxOf(a: T, b: T, comparator: Comparator<T>): T =
    if (comparator.compare(a, b) >= 0) a else b

public inline fun <T> maxOf(a: T, b: T, c: T, comparator: Comparator<T>): T =
    maxOf(maxOf(a, b, comparator), c, comparator)

public inline fun <T> maxOf(a: T, vararg other: T, comparator: Comparator<T>): T {
    var result = a
    var i = 0
    while (i < other.size) {
        result = maxOf(result, other[i], comparator)
        i += 1
    }
    return result
}

public inline fun <T> minOf(a: T, b: T, comparator: Comparator<T>): T =
    if (comparator.compare(a, b) <= 0) a else b

public inline fun <T> minOf(a: T, b: T, c: T, comparator: Comparator<T>): T =
    minOf(minOf(a, b, comparator), c, comparator)

public inline fun <T> minOf(a: T, vararg other: T, comparator: Comparator<T>): T {
    var result = a
    var i = 0
    while (i < other.size) {
        result = minOf(result, other[i], comparator)
        i += 1
    }
    return result
}

// Signed primitive overloads

public inline fun maxOf(a: Int, b: Int): Int = if (a >= b) a else b
public inline fun maxOf(a: Int, b: Int, c: Int): Int = maxOf(maxOf(a, b), c)
public inline fun maxOf(a: Int, vararg other: Int): Int {
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
public inline fun minOf(a: Int, vararg other: Int): Int {
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
public inline fun maxOf(a: Long, vararg other: Long): Long {
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
public inline fun minOf(a: Long, vararg other: Long): Long {
    var result = a
    var i = 0
    while (i < other.size) {
        result = minOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun maxOf(a: Float, b: Float): Float = kk_max_float(a, b)
public inline fun maxOf(a: Float, b: Float, c: Float): Float = maxOf(maxOf(a, b), c)
public inline fun maxOf(a: Float, vararg other: Float): Float {
    var result = a
    var i = 0
    while (i < other.size) {
        result = maxOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun minOf(a: Float, b: Float): Float = kk_min_float(a, b)
public inline fun minOf(a: Float, b: Float, c: Float): Float = minOf(minOf(a, b), c)
public inline fun minOf(a: Float, vararg other: Float): Float {
    var result = a
    var i = 0
    while (i < other.size) {
        result = minOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun maxOf(a: Double, b: Double): Double = kk_max_double(a, b)
public inline fun maxOf(a: Double, b: Double, c: Double): Double = maxOf(maxOf(a, b), c)
public inline fun maxOf(a: Double, vararg other: Double): Double {
    var result = a
    var i = 0
    while (i < other.size) {
        result = maxOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun minOf(a: Double, b: Double): Double = kk_min_double(a, b)
public inline fun minOf(a: Double, b: Double, c: Double): Double = minOf(minOf(a, b), c)
public inline fun minOf(a: Double, vararg other: Double): Double {
    var result = a
    var i = 0
    while (i < other.size) {
        result = minOf(result, other[i])
        i += 1
    }
    return result
}

// Unsigned primitive overloads

public inline fun maxOf(a: UByte, b: UByte): UByte = if (a >= b) a else b
public inline fun maxOf(a: UByte, b: UByte, c: UByte): UByte = maxOf(maxOf(a, b), c)
public inline fun maxOf(a: UByte, vararg other: UByte): UByte {
    var result = a
    var i = 0
    while (i < other.size) {
        result = maxOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun minOf(a: UByte, b: UByte): UByte = if (a <= b) a else b
public inline fun minOf(a: UByte, b: UByte, c: UByte): UByte = minOf(minOf(a, b), c)
public inline fun minOf(a: UByte, vararg other: UByte): UByte {
    var result = a
    var i = 0
    while (i < other.size) {
        result = minOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun maxOf(a: UShort, b: UShort): UShort = if (a >= b) a else b
public inline fun maxOf(a: UShort, b: UShort, c: UShort): UShort = maxOf(maxOf(a, b), c)
public inline fun maxOf(a: UShort, vararg other: UShort): UShort {
    var result = a
    var i = 0
    while (i < other.size) {
        result = maxOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun minOf(a: UShort, b: UShort): UShort = if (a <= b) a else b
public inline fun minOf(a: UShort, b: UShort, c: UShort): UShort = minOf(minOf(a, b), c)
public inline fun minOf(a: UShort, vararg other: UShort): UShort {
    var result = a
    var i = 0
    while (i < other.size) {
        result = minOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun maxOf(a: UInt, b: UInt): UInt = if (a >= b) a else b
public inline fun maxOf(a: UInt, b: UInt, c: UInt): UInt = maxOf(maxOf(a, b), c)
public inline fun maxOf(a: UInt, vararg other: UInt): UInt {
    var result = a
    var i = 0
    while (i < other.size) {
        result = maxOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun minOf(a: UInt, b: UInt): UInt = if (a <= b) a else b
public inline fun minOf(a: UInt, b: UInt, c: UInt): UInt = minOf(minOf(a, b), c)
public inline fun minOf(a: UInt, vararg other: UInt): UInt {
    var result = a
    var i = 0
    while (i < other.size) {
        result = minOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun maxOf(a: ULong, b: ULong): ULong = if (a >= b) a else b
public inline fun maxOf(a: ULong, b: ULong, c: ULong): ULong = maxOf(maxOf(a, b), c)
public inline fun maxOf(a: ULong, vararg other: ULong): ULong {
    var result = a
    var i = 0
    while (i < other.size) {
        result = maxOf(result, other[i])
        i += 1
    }
    return result
}

public inline fun minOf(a: ULong, b: ULong): ULong = if (a <= b) a else b
public inline fun minOf(a: ULong, b: ULong, c: ULong): ULong = minOf(minOf(a, b), c)
public inline fun minOf(a: ULong, vararg other: ULong): ULong {
    var result = a
    var i = 0
    while (i < other.size) {
        result = minOf(result, other[i])
        i += 1
    }
    return result
}
