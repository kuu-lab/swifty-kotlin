package kotlin.collections

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

public inline fun <T, R : Any> Array<out T>.mapIndexedNotNull(transform: (Int, T) -> R?): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    val sz = this.size
    while (i < sz) {
        val mapped = transform(i, this[i])
        if (mapped != null) result.add(mapped)
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

public fun <T, R> Array<T>.flatMap(transform: (T) -> Iterable<R>): List<R> {
    val result = mutableListOf<R>()
    var i = 0
    val sz = this.size
    while (i < sz) {
        val nestedIterator = transform(this[i]).iterator()
        while (nestedIterator.hasNext()) result.add(nestedIterator.next())
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

// `joinTo` / `joinToString` delegate to the source-backed Iterable
// implementations through the array's view. Primitive arrays retain their
// type-aware synthetic bridges until KSP-687.

public fun <T> Array<T>.joinTo(
    buffer: StringBuilder,
    separator: String = ", ",
    prefix: String = "",
    postfix: String = ""
): StringBuilder = this.asList().joinTo(buffer, separator, prefix, postfix)

public fun <T> Array<T>.joinTo(
    buffer: StringBuilder,
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String
): StringBuilder = this.asList().joinTo(buffer, separator, prefix, postfix, limit, truncated)

public fun <T> Array<T>.joinTo(
    buffer: StringBuilder,
    separator: String = ", ",
    prefix: String = "",
    postfix: String = "",
    limit: Int = -1,
    truncated: String = "...",
    transform: (T) -> Any
): StringBuilder = this.asList().joinTo(buffer, separator, prefix, postfix, limit, truncated) { transform(it).toString() }

public fun <T> Array<T>.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = ""
): String = this.asList().joinToString(separator, prefix, postfix)

public fun <T> Array<T>.joinToString(
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String
): String = this.asList().joinToString(separator, prefix, postfix, limit, truncated)

public fun <T> Array<T>.joinToString(
    separator: String,
    prefix: String,
    postfix: String,
    transform: (T) -> Any
): String = this.asList().joinToString(separator, prefix, postfix) { transform(it).toString() }

public fun <T> Array<T>.joinToString(transform: (T) -> Any): String =
    this.asList().joinToString { transform(it).toString() }

public fun <T> Array<T>.joinToString(separator: String, transform: (T) -> Any): String =
    this.asList().joinToString(separator) { transform(it).toString() }

public fun <T> Array<T>.joinToString(separator: String, prefix: String, transform: (T) -> Any): String =
    this.asList().joinToString(separator, prefix) { transform(it).toString() }

public fun <T> Array<T>.joinToString(
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String,
    transform: (T) -> Any
): String = this.asList().joinToString(separator, prefix, postfix, limit, truncated) { transform(it).toString() }

public fun <T> Array<T>.asSequence(): Sequence<T> = this.toList().asSequence()
