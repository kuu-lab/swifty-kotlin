package kotlin.collections

public fun Array<*>.any(): Boolean {
    return this.size > 0
}

public fun Array<*>.none(): Boolean {
    return this.size == 0
}

public inline fun <T> Array<T>.any(predicate: (T) -> Boolean): Boolean {
    var i = 0
    val sz = this.size
    while (i < sz) {
        if (predicate(this[i])) return true
        i++
    }
    return false
}

public inline fun <T> Array<T>.none(predicate: (T) -> Boolean): Boolean {
    var i = 0
    val sz = this.size
    while (i < sz) {
        if (predicate(this[i])) return false
        i++
    }
    return true
}
