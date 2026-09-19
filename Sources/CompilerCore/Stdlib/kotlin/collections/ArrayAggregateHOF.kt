package kotlin.collections

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
