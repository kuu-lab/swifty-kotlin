package kotlin.collections

import kotlin.experimental.ExperimentalTypeInference

// KSP-433: Array<T> fold/reduce HOFs are bundled Kotlin source. Primitive-array
// variants are defined in PrimitiveArrayHOF.kt.
//
// The empty-receiver message is "Empty array can't be reduced." (verified
// against kotlinc), distinct from the List/Iterable wording.

public fun <T, R> Array<T>.fold(initial: R, operation: (R, T) -> R): R {
    var acc = initial
    var i = 0
    val sz = this.size
    while (i < sz) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <T, R> Array<T>.foldIndexed(initial: R, operation: (Int, R, T) -> R): R {
    var acc = initial
    var i = 0
    val sz = this.size
    while (i < sz) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun <T> Array<T>.reduce(operation: (T, T) -> T): T {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    val sz = this.size
    while (i < sz) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <T> Array<T>.reduceIndexed(operation: (Int, T, T) -> T): T {
    if (this.size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var acc = this[0]
    var i = 1
    val sz = this.size
    while (i < sz) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

public fun <T> Array<T>.reduceOrNull(operation: (T, T) -> T): T? {
    if (this.size == 0) return null
    var acc = this[0]
    var i = 1
    val sz = this.size
    while (i < sz) {
        acc = operation(acc, this[i])
        i++
    }
    return acc
}

public fun <T> Array<T>.reduceIndexedOrNull(operation: (Int, T, T) -> T): T? {
    if (this.size == 0) return null
    var acc = this[0]
    var i = 1
    val sz = this.size
    while (i < sz) {
        acc = operation(i, acc, this[i])
        i++
    }
    return acc
}

@SinceKotlin("1.4")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun <T> Array<out T>.sumOf(selector: (T) -> Double): Double {
    var sum = 0.0
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
public inline fun <T> Array<out T>.sumOf(selector: (T) -> Int): Int {
    var sum = 0
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun <T> Array<out T>.sumOf(selector: (T) -> Long): Long {
    var sum = 0L
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.5")
public inline fun <T> Array<out T>.sumOf(selector: (T) -> UInt): UInt {
    var sum = 0u
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.5")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun <T> Array<out T>.sumOf(selector: (T) -> ULong): ULong {
    var sum = 0uL
    for (element in this) sum += selector(element)
    return sum
}

// KUU-1256: numeric and right-to-left aggregation on generic arrays.

public fun Array<out Byte>.sum(): Int = asIterable().sum()

public fun Array<out Byte>.average(): Double = asIterable().average()

public fun Array<out Short>.sum(): Int = asIterable().sum()

public fun Array<out Short>.average(): Double = asIterable().average()

public fun Array<out Int>.sum(): Int = asIterable().sum()

public fun Array<out Int>.average(): Double = asIterable().average()

public fun Array<out Long>.sum(): Long = asIterable().sum()

public fun Array<out Long>.average(): Double = asIterable().average()

public fun Array<out Float>.sum(): Float = asIterable().sum()

public fun Array<out Float>.average(): Double = asIterable().average()

public fun Array<out Double>.sum(): Double = asIterable().sum()

public fun Array<out Double>.average(): Double = asIterable().average()

public fun <T : Comparable<T>> Array<out T>.min(): T = asList().min()

public fun <T : Comparable<T>> Array<out T>.max(): T = asList().max()

public fun <T : Comparable<T>> Array<out T>.minOrNull(): T? = asList().minOrNull()

public fun <T : Comparable<T>> Array<out T>.maxOrNull(): T? = asList().maxOrNull()

public inline fun <T, R> Array<out T>.foldRight(initial: R, operation: (T, R) -> R): R {
    var accumulator = initial
    var index = size - 1
    while (index >= 0) {
        accumulator = operation(this[index], accumulator)
        index--
    }
    return accumulator
}

public inline fun <S, T : S> Array<out T>.reduceRight(operation: (T, S) -> S): S {
    if (size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var accumulator: S = this[size - 1]
    var index = size - 2
    while (index >= 0) {
        accumulator = operation(this[index], accumulator)
        index--
    }
    return accumulator
}

public inline fun <T, R> Array<out T>.scan(initial: R, operation: (R, T) -> R): List<R> =
    runningFold(initial, operation)

public inline fun <T, R> Array<out T>.runningFold(initial: R, operation: (R, T) -> R): List<R> {
    val result = mutableListOf<R>()
    var accumulator = initial
    result.add(accumulator)
    for (element in this) {
        accumulator = operation(accumulator, element)
        result.add(accumulator)
    }
    return result
}

public fun Array<out Double>.minOrNull(): Double? {
    if (size == 0) return null
    var result = this[0]
    var index = 1
    while (index < size) {
        result = kotlin.math.min(result, this[index])
        index++
    }
    return result
}

public fun Array<out Double>.min(): Double = minOrNull() ?: throw NoSuchElementException()

public fun Array<out Double>.maxOrNull(): Double? {
    if (size == 0) return null
    var result = this[0]
    var index = 1
    while (index < size) {
        result = kotlin.math.max(result, this[index])
        index++
    }
    return result
}

public fun Array<out Double>.max(): Double = maxOrNull() ?: throw NoSuchElementException()

public fun Array<out Float>.minOrNull(): Float? {
    if (size == 0) return null
    var result = this[0]
    var index = 1
    while (index < size) {
        result = kotlin.math.min(result, this[index])
        index++
    }
    return result
}

public fun Array<out Float>.min(): Float = minOrNull() ?: throw NoSuchElementException()

public fun Array<out Float>.maxOrNull(): Float? {
    if (size == 0) return null
    var result = this[0]
    var index = 1
    while (index < size) {
        result = kotlin.math.max(result, this[index])
        index++
    }
    return result
}

public fun Array<out Float>.max(): Float = maxOrNull() ?: throw NoSuchElementException()
