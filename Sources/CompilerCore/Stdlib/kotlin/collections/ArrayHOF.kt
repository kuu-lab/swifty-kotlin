package kotlin.collections

// KSP-433: Array<T> transform HOFs are bundled Kotlin source. Primitive-array
// variants are defined in PrimitiveArrayHOF.kt.

public fun <T, R> Array<T>.map(transform: (T) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    val sz = this.size
    while (i < sz) {
        result.add(transform(this[i]))
        i++
    }
    return result
}

public fun <T, R> Array<T>.mapIndexed(transform: (Int, T) -> R): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    val sz = this.size
    while (i < sz) {
        result.add(transform(i, this[i]))
        i++
    }
    return result
}

public fun <T, R : Any> Array<T>.mapNotNull(transform: (T) -> R?): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    val sz = this.size
    while (i < sz) {
        val mapped = transform(this[i])
        if (mapped != null) result.add(mapped)
        i++
    }
    return result
}

public fun <T, R> Array<T>.flatMap(transform: (T) -> List<R>): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    val sz = this.size
    while (i < sz) {
        val nested = transform(this[i])
        var j = 0
        val nestedSize = nested.size
        while (j < nestedSize) {
            result.add(nested[j])
            j++
        }
        i++
    }
    return result
}

public fun <T> Array<T>.forEach(action: (T) -> Unit) {
    var i = 0
    val sz = this.size
    while (i < sz) {
        action(this[i])
        i++
    }
}

// `joinToString` / `asSequence` delegate to the source-backed List
// implementations so Array and List share one rendering and one Sequence
// adapter. Both overloads are source-backed; the legacy synthetic member stubs
// are retained only for unresolved legacy call sites.

public fun <T> Array<T>.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = ""
): String = this.toList().joinToString(separator, prefix, postfix)

public fun <T> Array<T>.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = "",
    transform: (T) -> String
): String {
    val sb = StringBuilder()
    sb.append(prefix)
    var i = 0
    val sz = this.size
    while (i < sz) {
        if (i > 0) sb.append(separator)
        sb.append(transform(this[i]))
        i++
    }
    sb.append(postfix)
    return sb.toString()
}

public fun <T> Array<T>.asSequence(): Sequence<T> = this.toList().asSequence()
