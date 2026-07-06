package kotlin.comparisons

// MIGRATION-COMP-002
// maxOf/minOf overloads migrated to bundled Kotlin source. Call lowering keeps
// using the existing comparison fast paths so primitive and comparator calls
// preserve the runtime behavior while the public surface is source-backed.

public inline fun <T : Comparable<T>> maxOf(a: T, b: T): T =
    if (a >= b) a else b

public inline fun <T : Comparable<T>> maxOf(a: T, b: T, c: T): T {
    val best = if (a >= b) a else b
    return if (best >= c) best else c
}

public inline fun <T : Comparable<T>> maxOf(a: T, vararg other: T): T {
    var best = a
    for (candidate in other) {
        if (candidate > best) best = candidate
    }
    return best
}

public inline fun <T : Comparable<T>> minOf(a: T, b: T): T =
    if (a <= b) a else b

public inline fun <T : Comparable<T>> minOf(a: T, b: T, c: T): T {
    val best = if (a <= b) a else b
    return if (best <= c) best else c
}

public inline fun <T : Comparable<T>> minOf(a: T, vararg other: T): T {
    var best = a
    for (candidate in other) {
        if (candidate < best) best = candidate
    }
    return best
}

public inline fun maxOf(a: Int, b: Int): Int =
    if (a >= b) a else b

public inline fun maxOf(a: Int, b: Int, c: Int): Int {
    val best = if (a >= b) a else b
    return if (best >= c) best else c
}

public inline fun maxOf(a: Int, vararg other: Int): Int {
    var best = a
    for (candidate in other) {
        if (candidate > best) best = candidate
    }
    return best
}

public inline fun minOf(a: Int, b: Int): Int =
    if (a <= b) a else b

public inline fun minOf(a: Int, b: Int, c: Int): Int {
    val best = if (a <= b) a else b
    return if (best <= c) best else c
}

public inline fun minOf(a: Int, vararg other: Int): Int {
    var best = a
    for (candidate in other) {
        if (candidate < best) best = candidate
    }
    return best
}

public inline fun maxOf(a: Long, b: Long): Long =
    if (a >= b) a else b

public inline fun maxOf(a: Long, b: Long, c: Long): Long {
    val best = if (a >= b) a else b
    return if (best >= c) best else c
}

public inline fun maxOf(a: Long, vararg other: Long): Long {
    var best = a
    for (candidate in other) {
        if (candidate > best) best = candidate
    }
    return best
}

public inline fun minOf(a: Long, b: Long): Long =
    if (a <= b) a else b

public inline fun minOf(a: Long, b: Long, c: Long): Long {
    val best = if (a <= b) a else b
    return if (best <= c) best else c
}

public inline fun minOf(a: Long, vararg other: Long): Long {
    var best = a
    for (candidate in other) {
        if (candidate < best) best = candidate
    }
    return best
}

public inline fun maxOf(a: Float, b: Float): Float =
    if (a >= b) a else b

public inline fun maxOf(a: Float, b: Float, c: Float): Float {
    val best = if (a >= b) a else b
    return if (best >= c) best else c
}

public inline fun maxOf(a: Float, vararg other: Float): Float {
    var best = a
    for (candidate in other) {
        if (candidate > best) best = candidate
    }
    return best
}

public inline fun minOf(a: Float, b: Float): Float =
    if (a <= b) a else b

public inline fun minOf(a: Float, b: Float, c: Float): Float {
    val best = if (a <= b) a else b
    return if (best <= c) best else c
}

public inline fun minOf(a: Float, vararg other: Float): Float {
    var best = a
    for (candidate in other) {
        if (candidate < best) best = candidate
    }
    return best
}

public inline fun maxOf(a: Double, b: Double): Double =
    if (a >= b) a else b

public inline fun maxOf(a: Double, b: Double, c: Double): Double {
    val best = if (a >= b) a else b
    return if (best >= c) best else c
}

public inline fun maxOf(a: Double, vararg other: Double): Double {
    var best = a
    for (candidate in other) {
        if (candidate > best) best = candidate
    }
    return best
}

public inline fun minOf(a: Double, b: Double): Double =
    if (a <= b) a else b

public inline fun minOf(a: Double, b: Double, c: Double): Double {
    val best = if (a <= b) a else b
    return if (best <= c) best else c
}

public inline fun minOf(a: Double, vararg other: Double): Double {
    var best = a
    for (candidate in other) {
        if (candidate < best) best = candidate
    }
    return best
}

public inline fun maxOf(a: UByte, b: UByte): UByte =
    if (a >= b) a else b

public inline fun maxOf(a: UByte, b: UByte, c: UByte): UByte {
    val best = if (a >= b) a else b
    return if (best >= c) best else c
}

public inline fun maxOf(a: UByte, vararg other: UByte): UByte {
    var best = a
    for (candidate in other) {
        if (candidate > best) best = candidate
    }
    return best
}

public inline fun minOf(a: UByte, b: UByte): UByte =
    if (a <= b) a else b

public inline fun minOf(a: UByte, b: UByte, c: UByte): UByte {
    val best = if (a <= b) a else b
    return if (best <= c) best else c
}

public inline fun minOf(a: UByte, vararg other: UByte): UByte {
    var best = a
    for (candidate in other) {
        if (candidate < best) best = candidate
    }
    return best
}

public inline fun maxOf(a: UShort, b: UShort): UShort =
    if (a >= b) a else b

public inline fun maxOf(a: UShort, b: UShort, c: UShort): UShort {
    val best = if (a >= b) a else b
    return if (best >= c) best else c
}

public inline fun maxOf(a: UShort, vararg other: UShort): UShort {
    var best = a
    for (candidate in other) {
        if (candidate > best) best = candidate
    }
    return best
}

public inline fun minOf(a: UShort, b: UShort): UShort =
    if (a <= b) a else b

public inline fun minOf(a: UShort, b: UShort, c: UShort): UShort {
    val best = if (a <= b) a else b
    return if (best <= c) best else c
}

public inline fun minOf(a: UShort, vararg other: UShort): UShort {
    var best = a
    for (candidate in other) {
        if (candidate < best) best = candidate
    }
    return best
}

public inline fun maxOf(a: UInt, b: UInt): UInt =
    if (a >= b) a else b

public inline fun maxOf(a: UInt, b: UInt, c: UInt): UInt {
    val best = if (a >= b) a else b
    return if (best >= c) best else c
}

public inline fun maxOf(a: UInt, vararg other: UInt): UInt {
    var best = a
    for (candidate in other) {
        if (candidate > best) best = candidate
    }
    return best
}

public inline fun minOf(a: UInt, b: UInt): UInt =
    if (a <= b) a else b

public inline fun minOf(a: UInt, b: UInt, c: UInt): UInt {
    val best = if (a <= b) a else b
    return if (best <= c) best else c
}

public inline fun minOf(a: UInt, vararg other: UInt): UInt {
    var best = a
    for (candidate in other) {
        if (candidate < best) best = candidate
    }
    return best
}

public inline fun maxOf(a: ULong, b: ULong): ULong =
    if (a >= b) a else b

public inline fun maxOf(a: ULong, b: ULong, c: ULong): ULong {
    val best = if (a >= b) a else b
    return if (best >= c) best else c
}

public inline fun maxOf(a: ULong, vararg other: ULong): ULong {
    var best = a
    for (candidate in other) {
        if (candidate > best) best = candidate
    }
    return best
}

public inline fun minOf(a: ULong, b: ULong): ULong =
    if (a <= b) a else b

public inline fun minOf(a: ULong, b: ULong, c: ULong): ULong {
    val best = if (a <= b) a else b
    return if (best <= c) best else c
}

public inline fun minOf(a: ULong, vararg other: ULong): ULong {
    var best = a
    for (candidate in other) {
        if (candidate < best) best = candidate
    }
    return best
}

public inline fun <T> maxOf(a: T, b: T, comparator: Comparator<T>): T =
    if (comparator.compare(a, b) >= 0) a else b

public inline fun <T> maxOf(a: T, b: T, c: T, comparator: Comparator<T>): T {
    val best = if (comparator.compare(a, b) >= 0) a else b
    return if (comparator.compare(best, c) >= 0) best else c
}

public inline fun <T> maxOf(a: T, vararg other: T, comparator: Comparator<T>): T {
    var best = a
    for (candidate in other) {
        if (comparator.compare(candidate, best) > 0) best = candidate
    }
    return best
}

public inline fun <T> minOf(a: T, b: T, comparator: Comparator<T>): T =
    if (comparator.compare(a, b) <= 0) a else b

public inline fun <T> minOf(a: T, b: T, c: T, comparator: Comparator<T>): T {
    val best = if (comparator.compare(a, b) <= 0) a else b
    return if (comparator.compare(best, c) <= 0) best else c
}

public inline fun <T> minOf(a: T, vararg other: T, comparator: Comparator<T>): T {
    var best = a
    for (candidate in other) {
        if (comparator.compare(candidate, best) < 0) best = candidate
    }
    return best
}
