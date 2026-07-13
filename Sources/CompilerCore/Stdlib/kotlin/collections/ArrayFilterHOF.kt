package kotlin.collections

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
