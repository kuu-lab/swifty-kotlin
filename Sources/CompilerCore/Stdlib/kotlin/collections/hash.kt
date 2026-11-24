package kotlin.collections

public inline fun <K, V> hashMapOf(): HashMap<K, V> = mutableMapOf()

public fun <K, V> hashMapOf(vararg pairs: Pair<K, V>): HashMap<K, V> {
    val result: HashMap<K, V> = mutableMapOf()
    for (pair in pairs) {
        result[pair.first] = pair.second
    }
    return result
}

public inline fun <T> hashSetOf(): HashSet<T> = HashSet()

public fun <T> hashSetOf(vararg elements: T): HashSet<T> {
    val result = HashSet<T>()
    for (element in elements) {
        result.add(element)
    }
    return result
}
