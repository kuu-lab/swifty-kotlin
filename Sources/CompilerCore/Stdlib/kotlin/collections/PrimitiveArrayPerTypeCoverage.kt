package kotlin.collections

import kotlin.experimental.ExperimentalTypeInference

// Per-type coverage for primitive-array extensions (KUU-2781). The same API surface
// exists for List/Iterable and Array<T>; these fill the receiver types that were missing.

public inline fun BooleanArray.isNotEmpty(): Boolean = size != 0

public inline fun ShortArray.isNotEmpty(): Boolean = size != 0

public inline fun CharArray.isNotEmpty(): Boolean = size != 0

public inline fun IntArray.isNotEmpty(): Boolean = size != 0

public inline fun LongArray.isNotEmpty(): Boolean = size != 0

public inline fun FloatArray.isNotEmpty(): Boolean = size != 0

public inline fun DoubleArray.isNotEmpty(): Boolean = size != 0

public inline fun <T> Array<out T>.isNotEmpty(): Boolean = size != 0

public fun BooleanArray.distinct(): List<Boolean> = asList().distinct()

public fun ByteArray.distinct(): List<Byte> = asList().distinct()

public fun ShortArray.distinct(): List<Short> = asList().distinct()

public fun CharArray.distinct(): List<Char> = asList().distinct()

public fun IntArray.distinct(): List<Int> = asList().distinct()

public fun LongArray.distinct(): List<Long> = asList().distinct()

public fun FloatArray.distinct(): List<Float> = asList().distinct()

public fun DoubleArray.distinct(): List<Double> = asList().distinct()

public fun BooleanArray.withIndex(): Iterable<IndexedValue<Boolean>> {
    val array = this
    return object : Iterable<IndexedValue<Boolean>> {
        override fun iterator(): Iterator<IndexedValue<Boolean>> = IndexingIterator(array.iterator())
    }
}

public fun CharArray.withIndex(): Iterable<IndexedValue<Char>> {
    val array = this
    return object : Iterable<IndexedValue<Char>> {
        override fun iterator(): Iterator<IndexedValue<Char>> = IndexingIterator(array.iterator())
    }
}

public fun FloatArray.withIndex(): Iterable<IndexedValue<Float>> {
    val array = this
    return object : Iterable<IndexedValue<Float>> {
        override fun iterator(): Iterator<IndexedValue<Float>> = IndexingIterator(array.iterator())
    }
}

public fun DoubleArray.withIndex(): Iterable<IndexedValue<Double>> {
    val array = this
    return object : Iterable<IndexedValue<Double>> {
        override fun iterator(): Iterator<IndexedValue<Double>> = IndexingIterator(array.iterator())
    }
}

public fun ByteArray.sorted(): List<Byte> = sortedArray().toList()

public fun ShortArray.sorted(): List<Short> = sortedArray().toList()

public fun CharArray.sorted(): List<Char> = sortedArray().toList()

public fun LongArray.sorted(): List<Long> = sortedArray().toList()

public fun FloatArray.sorted(): List<Float> = sortedArray().toList()

public fun DoubleArray.sorted(): List<Double> = sortedArray().toList()

@SinceKotlin("1.4")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun BooleanArray.sumOf(selector: (Boolean) -> Double): Double {
    var sum = 0.0
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
public inline fun BooleanArray.sumOf(selector: (Boolean) -> Int): Int {
    var sum = 0
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun BooleanArray.sumOf(selector: (Boolean) -> Long): Long {
    var sum = 0L
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.5")
public inline fun BooleanArray.sumOf(selector: (Boolean) -> UInt): UInt {
    var sum = 0u
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.5")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun BooleanArray.sumOf(selector: (Boolean) -> ULong): ULong {
    var sum = 0uL
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun ByteArray.sumOf(selector: (Byte) -> Double): Double {
    var sum = 0.0
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
public inline fun ByteArray.sumOf(selector: (Byte) -> Int): Int {
    var sum = 0
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun ByteArray.sumOf(selector: (Byte) -> Long): Long {
    var sum = 0L
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.5")
public inline fun ByteArray.sumOf(selector: (Byte) -> UInt): UInt {
    var sum = 0u
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.5")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun ByteArray.sumOf(selector: (Byte) -> ULong): ULong {
    var sum = 0uL
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun ShortArray.sumOf(selector: (Short) -> Double): Double {
    var sum = 0.0
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
public inline fun ShortArray.sumOf(selector: (Short) -> Int): Int {
    var sum = 0
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun ShortArray.sumOf(selector: (Short) -> Long): Long {
    var sum = 0L
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.5")
public inline fun ShortArray.sumOf(selector: (Short) -> UInt): UInt {
    var sum = 0u
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.5")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun ShortArray.sumOf(selector: (Short) -> ULong): ULong {
    var sum = 0uL
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun IntArray.sumOf(selector: (Int) -> Double): Double {
    var sum = 0.0
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
public inline fun IntArray.sumOf(selector: (Int) -> Int): Int {
    var sum = 0
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun IntArray.sumOf(selector: (Int) -> Long): Long {
    var sum = 0L
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.5")
public inline fun IntArray.sumOf(selector: (Int) -> UInt): UInt {
    var sum = 0u
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.5")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun IntArray.sumOf(selector: (Int) -> ULong): ULong {
    var sum = 0uL
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun LongArray.sumOf(selector: (Long) -> Double): Double {
    var sum = 0.0
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
public inline fun LongArray.sumOf(selector: (Long) -> Int): Int {
    var sum = 0
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun LongArray.sumOf(selector: (Long) -> Long): Long {
    var sum = 0L
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.5")
public inline fun LongArray.sumOf(selector: (Long) -> UInt): UInt {
    var sum = 0u
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.5")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun LongArray.sumOf(selector: (Long) -> ULong): ULong {
    var sum = 0uL
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun FloatArray.sumOf(selector: (Float) -> Double): Double {
    var sum = 0.0
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
public inline fun FloatArray.sumOf(selector: (Float) -> Int): Int {
    var sum = 0
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun FloatArray.sumOf(selector: (Float) -> Long): Long {
    var sum = 0L
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.5")
public inline fun FloatArray.sumOf(selector: (Float) -> UInt): UInt {
    var sum = 0u
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.5")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun FloatArray.sumOf(selector: (Float) -> ULong): ULong {
    var sum = 0uL
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun DoubleArray.sumOf(selector: (Double) -> Double): Double {
    var sum = 0.0
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
public inline fun DoubleArray.sumOf(selector: (Double) -> Int): Int {
    var sum = 0
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.4")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun DoubleArray.sumOf(selector: (Double) -> Long): Long {
    var sum = 0L
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.5")
public inline fun DoubleArray.sumOf(selector: (Double) -> UInt): UInt {
    var sum = 0u
    for (element in this) sum += selector(element)
    return sum
}

@SinceKotlin("1.5")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun DoubleArray.sumOf(selector: (Double) -> ULong): ULong {
    var sum = 0uL
    for (element in this) sum += selector(element)
    return sum
}
