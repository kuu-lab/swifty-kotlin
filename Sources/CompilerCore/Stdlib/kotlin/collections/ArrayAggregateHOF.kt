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
