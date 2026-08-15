package kotlin.collections

// KSP-433: Array<T> filter HOFs are bundled Kotlin source. Primitive-array
// variants are defined in PrimitiveArrayHOF.kt.

public fun <T> Array<T>.filter(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    val sz = this.size
    while (i < sz) {
        val element = this[i]
        if (predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun <T> Array<T>.filterIndexed(predicate: (Int, T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    val sz = this.size
    while (i < sz) {
        val element = this[i]
        if (predicate(i, element)) result.add(element)
        i++
    }
    return result
}

public fun <T> Array<T>.filterNot(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    val sz = this.size
    while (i < sz) {
        val element = this[i]
        if (!predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun <T : Any> Array<T?>.filterNotNull(): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    val sz = this.size
    while (i < sz) {
        val element = this[i]
        if (element != null) result.add(element)
        i++
    }
    return result
}

public inline fun <reified R> Array<*>.filterIsInstance(): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    val sz = this.size
    while (i < sz) {
        val element = this[i]
        if (element is R) result.add(element)
        i++
    }
    return result
}
