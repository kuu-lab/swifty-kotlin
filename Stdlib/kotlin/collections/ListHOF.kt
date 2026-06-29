package kotlin.collections

// MIGRATION-COL-002: List transform HOFs
// Migration source: Sources/Runtime/RuntimeCollectionHOF.swift (kk_list_map, kk_list_mapIndexed,
//                   kk_list_mapNotNull, kk_list_flatMap, kk_list_flatten)

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
