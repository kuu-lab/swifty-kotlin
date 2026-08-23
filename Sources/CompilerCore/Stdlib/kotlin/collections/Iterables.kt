package kotlin.collections

// KSP-435
// Generic Iterable<T> surface migrated from the Swift runtime `kk_iterable_*`
// bridges. Every implementation only relies on `iterator()` virtual dispatch,
// so it works for List, Set and any user-defined Iterable alike.

public fun <T> Iterable<T>.toList(): List<T> {
    val result = mutableListOf<T>()
    for (element in this) result.add(element)
    return result
}

public fun <T> Iterable<T>.toMutableList(): MutableList<T> {
    val result = mutableListOf<T>()
    for (element in this) result.add(element)
    return result
}

public fun <T> Iterable<T>.toMutableSet(): MutableSet<T> {
    val result = mutableSetOf<T>()
    for (element in this) result.add(element)
    return result
}

public fun <T> Iterable<T>.toHashSet(): HashSet<T> {
    val result = mutableSetOf<T>()
    for (element in this) result.add(element)
    return result
}

@IgnorableReturnValue
public fun <T, C : MutableCollection<in T>> Iterable<T>.toCollection(destination: C): C {
    for (element in this) destination.add(element)
    return destination
}

@Suppress("UNCHECKED_CAST")
public fun <K, V> Iterable<Pair<K, V>>.toMap(): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (pair in this) result[pair.first] = pair.second
    return result as Map<K, V>
}

@IgnorableReturnValue
@Suppress("UNCHECKED_CAST")
public fun <K, V, M : MutableMap<in K, in V>> Iterable<Pair<K, V>>.toMap(destination: M): M {
    // The bundled MutableMap stub exposes invariant operator parameters; the
    // official contravariant API permits every K/V write to this destination.
    val typedDestination = destination as MutableMap<K, V>
    for (pair in this) typedDestination[pair.first] = pair.second
    return destination
}

@Suppress("UNCHECKED_CAST")
public fun <T> Iterable<T>.toSet(): Set<T> {
    val result = mutableSetOf<T>()
    for (element in this) result.add(element)
    return result as Set<T>
}

public fun <T> Collection<T>.isNotEmpty(): Boolean = !isEmpty()

@Suppress("UNCHECKED_CAST")
public fun <T> Iterable<T>.last(): T {
    var found = false
    var last: T? = null
    for (element in this) {
        last = element
        found = true
    }
    if (!found) throw NoSuchElementException("Collection is empty.")
    return last as T
}

// KSP-701: generic Iterable HOFs formerly registered by the compiler-side
// synthetic member registry now use bundled Kotlin source bodies.
public fun <T> Iterable<T>.filter(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        if (predicate(element)) result.add(element)
    }
    return result
}

public fun <T> Iterable<T>.reduce(operation: (T, T) -> T): T {
    val elements = this.toMutableList()
    if (elements.isEmpty()) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = elements[0]
    var i = 1
    while (i < elements.size) {
        accumulator = operation(accumulator, elements[i])
        i += 1
    }
    return accumulator
}

public fun <T> Iterable<T>.reduceIndexed(operation: (Int, T, T) -> T): T {
    val elements = this.toMutableList()
    if (elements.isEmpty()) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = elements[0]
    var i = 1
    while (i < elements.size) {
        accumulator = operation(i, accumulator, elements[i])
        i += 1
    }
    return accumulator
}

public fun <T> Iterable<T>.any(): Boolean {
    for (element in this) return true
    return false
}

public fun <T> Iterable<T>.any(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (predicate(element)) return true
    }
    return false
}

public fun <T> Iterable<T>.all(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (!predicate(element)) return false
    }
    return true
}

public fun <T, R : Any> Iterable<T>.firstNotNullOfOrNull(transform: (T) -> R?): R? {
    for (element in this) {
        val result = transform(element)
        if (result != null) return result
    }
    return null
}

public fun <T, R : Any> Iterable<T>.firstNotNullOf(transform: (T) -> R?): R {
    for (element in this) {
        val result = transform(element)
        if (result != null) return result
    }
    throw NoSuchElementException("No element of the collection was transformed to a non-null value.")
}

@Suppress("UNCHECKED_CAST")
public fun <T : Any> Iterable<T?>.requireNoNulls(): Iterable<T> {
    for (element in this) {
        if (element == null) {
            throw IllegalArgumentException("null element found in $this.")
        }
    }
    return this as Iterable<T>
}

// Shared by Iterable.joinTo/joinToString (below) and Sequence.joinTo/joinToString
// (SequenceAggregateHOF.kt, kotlin.sequences) — both only need iterator(), so a
// single implementation keyed on Iterator<T> covers both receiver types (KSP-621).
internal fun <T> appendJoinToPlain(
    iterator: Iterator<T>,
    buffer: StringBuilder,
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String
): StringBuilder {
    buffer.append(prefix)
    var count = 0
    var hasMore = false
    while (iterator.hasNext()) {
        val element = iterator.next()
        if (limit >= 0 && count >= limit) {
            hasMore = true
            break
        }
        if (count > 0) buffer.append(separator)
        buffer.append(element.toString())
        count++
    }
    if (hasMore) {
        if (count > 0) buffer.append(separator)
        buffer.append(truncated)
    }
    buffer.append(postfix)
    return buffer
}

internal fun <T> appendJoinToTransform(
    iterator: Iterator<T>,
    buffer: StringBuilder,
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String,
    transform: (T) -> Any
): StringBuilder {
    buffer.append(prefix)
    var count = 0
    var hasMore = false
    while (iterator.hasNext()) {
        val element = iterator.next()
        if (limit >= 0 && count >= limit) {
            hasMore = true
            break
        }
        if (count > 0) buffer.append(separator)
        buffer.append(transform(element).toString())
        count++
    }
    if (hasMore) {
        if (count > 0) buffer.append(separator)
        buffer.append(truncated)
    }
    buffer.append(postfix)
    return buffer
}

public fun <T> Iterable<T>.joinTo(
    buffer: StringBuilder,
    separator: String = ", ",
    prefix: String = "",
    postfix: String = ""
): StringBuilder = appendJoinToPlain(this.iterator(), buffer, separator, prefix, postfix, -1, "...")

public fun <T> Iterable<T>.joinTo(
    buffer: StringBuilder,
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String
): StringBuilder = appendJoinToPlain(this.iterator(), buffer, separator, prefix, postfix, limit, truncated)

public fun <T> Iterable<T>.joinTo(
    buffer: StringBuilder,
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String,
    transform: (T) -> Any
): StringBuilder = appendJoinToTransform(this.iterator(), buffer, separator, prefix, postfix, limit, truncated, transform)

public fun <T> Iterable<T>.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = ""
): String = appendJoinToPlain(this.iterator(), StringBuilder(), separator, prefix, postfix, -1, "...").toString()

public fun <T> Iterable<T>.joinToString(
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String
): String = appendJoinToPlain(this.iterator(), StringBuilder(), separator, prefix, postfix, limit, truncated).toString()

// The `transform` overloads are spelled per arity because a trailing lambda
// cannot be bound to the defaulted `String` parameters above.
public fun <T> Iterable<T>.joinToString(
    separator: String,
    prefix: String,
    postfix: String,
    transform: (T) -> Any
): String {
    return appendJoinToTransform(this.iterator(), StringBuilder(), separator, prefix, postfix, -1, "...", transform).toString()
}

public fun <T> Iterable<T>.joinToString(
    separator: String,
    prefix: String,
    transform: (T) -> Any
): String = joinToString(separator, prefix, "", transform)

public fun <T> Iterable<T>.joinToString(
    separator: String,
    transform: (T) -> Any
): String = joinToString(separator, "", "", transform)

public fun <T> Iterable<T>.joinToString(
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String,
    transform: (T) -> Any
): String = appendJoinToTransform(this.iterator(), StringBuilder(), separator, prefix, postfix, limit, truncated, transform).toString()

// KSP-632: remaining Iterable HOFs migrated from the Swift runtime `kk_list_*`
// bridges. These implementations rely only on `iterator()` / `toMutableList()`,
// so they work for List, Set and any other Iterable.

public fun <T> Iterable<T>.reduceRight(operation: (T, T) -> T): T {
    val list = this.toMutableList()
    if (list.size == 0) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = list[list.size - 1]
    var i = list.size - 2
    while (i >= 0) {
        accumulator = operation(list[i], accumulator)
        i -= 1
    }
    return accumulator
}

public fun <T> Iterable<T>.reduceRightIndexed(operation: (Int, T, T) -> T): T {
    val list = this.toMutableList()
    if (list.size == 0) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = list[list.size - 1]
    var i = list.size - 2
    while (i >= 0) {
        accumulator = operation(i, list[i], accumulator)
        i -= 1
    }
    return accumulator
}

public fun <T> Iterable<T>.reduceRightOrNull(operation: (T, T) -> T): T? {
    val list = this.toMutableList()
    if (list.size == 0) return null
    var accumulator = list[list.size - 1]
    var i = list.size - 2
    while (i >= 0) {
        accumulator = operation(list[i], accumulator)
        i -= 1
    }
    return accumulator
}

public fun <T> Iterable<T>.reduceRightIndexedOrNull(operation: (Int, T, T) -> T): T? {
    val list = this.toMutableList()
    if (list.size == 0) return null
    var accumulator = list[list.size - 1]
    var i = list.size - 2
    while (i >= 0) {
        accumulator = operation(i, list[i], accumulator)
        i -= 1
    }
    return accumulator
}

public fun <T> Iterable<T>.joinToString(
    transform: (T) -> Any
): String = appendJoinToTransform(this.iterator(), StringBuilder(), ", ", "", "", -1, "...", transform).toString()

// Char.toString() is represented by its numeric code in the generic path;
// keep the List<Char> overload aligned with Kotlin's character rendering.
public fun List<Char>.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = ""
): String {
    val buffer = StringBuilder()
    buffer.append(prefix)
    var first = true
    for (element in this) {
        if (!first) buffer.append(separator)
        buffer.append(element)
        first = false
    }
    buffer.append(postfix)
    return buffer.toString()
}
