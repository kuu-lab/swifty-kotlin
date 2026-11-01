package kotlin.collections

// MIGRATION-COL-002
// Migration source:
//   Sources/CompilerCore/Driver/BundledStdlib.swift (map, mapIndexed, mapNotNull, flatMap, flatten)

public inline fun <T, R> List<T>.map(transform: (T) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < size) { result.add(transform(this[i])); i += 1 }
    return result
}

public fun <T, R, C : MutableCollection<R>> List<T>.mapTo(destination: C, transform: (T) -> R): C {
    var i = 0
    while (i < size) { destination.add(transform(this[i])); i += 1 }
    return destination
}

public inline fun <T, R> List<T>.mapIndexed(transform: (Int, T) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < size) { result.add(transform(i, this[i])); i += 1 }
    return result
}

public fun <T, R, C : MutableCollection<R>> List<T>.mapIndexedTo(destination: C, transform: (Int, T) -> R): C {
    var i = 0
    while (i < size) { destination.add(transform(i, this[i])); i += 1 }
    return destination
}

public fun <T, R : Any> List<T>.mapIndexedNotNull(transform: (Int, T) -> R?): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < size) { val item = transform(i, this[i]); if (item != null) result.add(item); i += 1 }
    return result
}

public fun <T, R : Any, C : MutableCollection<R>> List<T>.mapIndexedNotNullTo(destination: C, transform: (Int, T) -> R?): C {
    var i = 0
    while (i < size) { val item = transform(i, this[i]); if (item != null) destination.add(item); i += 1 }
    return destination
}

public inline fun <T, R : Any> List<T>.mapNotNull(transform: (T) -> R?): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < size) { val item = transform(this[i]); if (item != null) result.add(item); i += 1 }
    return result
}

public fun <T, R : Any, C : MutableCollection<R>> List<T>.mapNotNullTo(destination: C, transform: (T) -> R?): C {
    var i = 0
    while (i < size) { val item = transform(this[i]); if (item != null) destination.add(item); i += 1 }
    return destination
}

// KUU-4060: these List specializations accept any Iterable transform result,
// matching the Kotlin stdlib's `Iterable<T>.flatMap(transform: (T) -> Iterable<R>)`
// surface. The previous `(T) -> List<R>` shape was bound even for lambdas
// returning other Iterables (ranges, sets), silently dropping all elements.
public inline fun <T, R> List<T>.flatMap(transform: (T) -> Iterable<R>): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < size) {
        val nestedIterator = transform(this[i]).iterator()
        while (nestedIterator.hasNext()) { result.add(nestedIterator.next()) }
        i += 1
    }
    return result
}

public fun <T, R, C : MutableCollection<R>> List<T>.flatMapTo(destination: C, transform: (T) -> Iterable<R>): C {
    var i = 0
    while (i < size) {
        val nestedIterator = transform(this[i]).iterator()
        while (nestedIterator.hasNext()) { destination.add(nestedIterator.next()) }
        i += 1
    }
    return destination
}

public fun <T, R> List<T>.flatMapIndexed(transform: (Int, T) -> Iterable<R>): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < size) {
        val nestedIterator = transform(i, this[i]).iterator()
        while (nestedIterator.hasNext()) { result.add(nestedIterator.next()) }
        i += 1
    }
    return result
}

public fun <T, R, C : MutableCollection<R>> List<T>.flatMapIndexedTo(destination: C, transform: (Int, T) -> Iterable<R>): C {
    var i = 0
    while (i < size) {
        val nestedIterator = transform(i, this[i]).iterator()
        while (nestedIterator.hasNext()) { destination.add(nestedIterator.next()) }
        i += 1
    }
    return destination
}

public fun <T> List<List<T>>.flatten(): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    while (i < size) {
        val sub = this[i]
        var j = 0
        while (j < sub.size) { result.add(sub[j]); j += 1 }
        i += 1
    }
    return result
}
