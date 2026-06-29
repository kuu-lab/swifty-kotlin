package kotlin.collections

// MIGRATION-COL-002
// List transform HOFs migrated to Kotlin source.
// Migration source:
//   Sources/CompilerCore/Driver/BundledKotlinStdlib.swift (map, mapIndexed, mapNotNull, flatMap, flatten)
//
// NOTE: Runtime ABI entry points are intentionally kept as bridge/compatibility
// helpers while stdlib-source dispatch is rolled out incrementally.

public fun <T, R> List<T>.map(transform: (T) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < size) { result.add(transform(this[i])); i += 1 }
    return result
}

public fun <T, R> List<T>.mapIndexed(transform: (Int, T) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < size) { result.add(transform(i, this[i])); i += 1 }
    return result
}

public fun <T, R : Any> List<T>.mapNotNull(transform: (T) -> R?): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < size) { val item = transform(this[i]); if (item != null) result.add(item); i += 1 }
    return result
}

public fun <T, R> List<T>.flatMap(transform: (T) -> List<R>): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    while (i < size) {
        val sub = transform(this[i])
        var j = 0
        while (j < sub.size) { result.add(sub[j]); j += 1 }
        i += 1
    }
    return result
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
