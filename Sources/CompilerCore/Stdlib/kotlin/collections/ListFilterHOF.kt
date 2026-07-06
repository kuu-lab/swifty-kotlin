package kotlin.collections

// MIGRATION-COL-003
// List filter HOFs migrated to Kotlin source.
// Migration source:
//   Sources/Runtime/RuntimeCollectionHOF.swift  (filter, filterNot, filterNotNull, filterIndexed, filterIsInstance)
//
// NOTE: Runtime ABI entry points are intentionally kept as bridge/compatibility
// helpers while stdlib-source dispatch is rolled out incrementally.

public fun <T> List<T>.filter(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun <T> List<T>.filterNot(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (!predicate(element)) result.add(element)
        i++
    }
    return result
}

public fun <T : Any> List<T?>.filterNotNull(): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (element != null) result.add(element)
        i++
    }
    return result
}

public fun <T> List<T>.filterIndexed(predicate: (Int, T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (predicate(i, element)) result.add(element)
        i++
    }
    return result
}

public inline fun <reified R> List<*>.filterIsInstance(): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (element is R) result.add(element)
        i++
    }
    return result
}
