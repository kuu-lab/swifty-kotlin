package kotlin.collections

@SinceKotlin("2.4")
@ExperimentalStdlibApi
public fun <T> Iterable<T>.allEqual(): Boolean {
    val elements = iterator()
    if (!elements.hasNext()) return true
    val first = elements.next()
    while (elements.hasNext()) {
        if (first != elements.next()) return false
    }
    return true
}

@SinceKotlin("2.4")
@ExperimentalStdlibApi
public inline fun <T, K> Iterable<T>.allEqualBy(selector: (T) -> K): Boolean {
    val elements = iterator()
    if (!elements.hasNext()) return true
    var element = elements.next()
    if (!elements.hasNext()) return true

    var firstKey: K? = null
    var isFirst = true
    while (true) {
        val key = selector(element)
        if (isFirst) {
            firstKey = key
            isFirst = false
        } else if (firstKey != key) {
            return false
        }
        if (!elements.hasNext()) break
        element = elements.next()
    }
    return true
}

@SinceKotlin("2.4")
@ExperimentalStdlibApi
public fun <T> Iterable<T>.allDistinct(): Boolean {
    val elements = iterator()
    if (!elements.hasNext()) return true
    val first = elements.next()
    if (!elements.hasNext()) return true

    val seen = HashSet<T>()
    seen.add(first)
    do {
        if (!seen.add(elements.next())) return false
    } while (elements.hasNext())
    return true
}

@SinceKotlin("2.4")
@ExperimentalStdlibApi
public inline fun <T, K> Iterable<T>.allDistinctBy(selector: (T) -> K): Boolean {
    val elements = iterator()
    if (!elements.hasNext()) return true
    var element = elements.next()
    if (!elements.hasNext()) return true

    val seen = HashSet<K>()
    while (true) {
        if (!seen.add(selector(element))) return false
        if (!elements.hasNext()) break
        element = elements.next()
    }
    return true
}

@SinceKotlin("2.4")
@ExperimentalStdlibApi
public fun <T> Array<out T>.allEqual(): Boolean {
    val length = size
    if (length < 2) return true
    val first = this[0]
    var index = 1
    while (index < length) {
        if (first != this[index]) return false
        index++
    }
    return true
}

@SinceKotlin("2.4")
@ExperimentalStdlibApi
public inline fun <T, K> Array<out T>.allEqualBy(selector: (T) -> K): Boolean {
    val length = size
    if (length < 2) return true
    var firstKey: K? = null
    var index = 0
    while (index < length) {
        val key = selector(this[index])
        if (index == 0) {
            firstKey = key
        } else if (firstKey != key) {
            return false
        }
        index++
    }
    return true
}

@SinceKotlin("2.4")
@ExperimentalStdlibApi
public fun <T> Array<out T>.allDistinct(): Boolean {
    val length = size
    if (length < 2) return true
    val seen = HashSet<T>()
    var index = 0
    while (index < length) {
        if (!seen.add(this[index])) return false
        index++
    }
    return true
}

@SinceKotlin("2.4")
@ExperimentalStdlibApi
public inline fun <T, K> Array<out T>.allDistinctBy(selector: (T) -> K): Boolean {
    val length = size
    if (length < 2) return true
    val seen = HashSet<K>()
    var index = 0
    while (index < length) {
        if (!seen.add(selector(this[index]))) return false
        index++
    }
    return true
}
