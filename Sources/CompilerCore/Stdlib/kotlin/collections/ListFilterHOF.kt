package kotlin.collections

// MIGRATION-COL-003
// List filter HOFs migrated to Kotlin source.
// Replaces the previous runtime-backed List filter helpers.

public fun <T> List<T>.filter(predicate: (T) -> Boolean): List<T> {
    return filterTo(mutableListOf<T>(), predicate)
}

public fun <T> List<T>.filterNot(predicate: (T) -> Boolean): List<T> {
    return filterNotTo(mutableListOf<T>(), predicate)
}

public fun <T : Any> List<T?>.filterNotNull(): List<T> {
    return filterNotNullTo(mutableListOf<T>())
}

public fun <T> List<T>.filterIndexed(predicate: (Int, T) -> Boolean): List<T> {
    return filterIndexedTo(mutableListOf<T>(), predicate)
}

public inline fun <reified R : Any> List<*>.filterIsInstance(): List<R> {
    val destination = mutableListOf<R>()
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (element is R) destination.add(element)
        i++
    }
    return destination
}

public fun <T, C : MutableCollection<T>> List<T>.filterTo(
    destination: C,
    predicate: (T) -> Boolean
): C {
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (predicate(element)) destination.add(element)
        i++
    }
    return destination
}

public fun <T, C : MutableCollection<T>> List<T>.filterNotTo(
    destination: C,
    predicate: (T) -> Boolean
): C {
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (!predicate(element)) destination.add(element)
        i++
    }
    return destination
}

public fun <T : Any, C : MutableCollection<T>> List<T?>.filterNotNullTo(
    destination: C
): C {
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (element != null) destination.add(element)
        i++
    }
    return destination
}

public fun <T, C : MutableCollection<T>> List<T>.filterIndexedTo(
    destination: C,
    predicate: (Int, T) -> Boolean
): C {
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (predicate(i, element)) destination.add(element)
        i++
    }
    return destination
}

public inline fun <reified R : Any, C : MutableCollection<R>> List<*>.filterIsInstanceTo(
    destination: C
): C {
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (element is R) destination.add(element)
        i++
    }
    return destination
}
