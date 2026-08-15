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

public fun <T> Iterable<T>.toHashSet(): MutableSet<T> {
    val result = mutableSetOf<T>()
    for (element in this) result.add(element)
    return result
}

public fun <T, C : MutableCollection<in T>> Iterable<T>.toCollection(destination: C): C {
    for (element in this) destination.add(element)
    return destination
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

public fun <T> Iterable<T>.joinTo(
    buffer: StringBuilder,
    separator: String = ", ",
    prefix: String = "",
    postfix: String = ""
): StringBuilder {
    buffer.append(prefix)
    var first = true
    for (element in this) {
        if (!first) buffer.append(separator)
        buffer.append(element.toString())
        first = false
    }
    buffer.append(postfix)
    return buffer
}

public fun <T> Iterable<T>.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = ""
): String = joinTo(StringBuilder(), separator, prefix, postfix).toString()

// The `transform` overloads are spelled per arity because a trailing lambda
// cannot be bound to the defaulted `String` parameters above.
public fun <T> Iterable<T>.joinToString(
    separator: String,
    prefix: String,
    postfix: String,
    transform: (T) -> Any
): String {
    val buffer = StringBuilder()
    buffer.append(prefix)
    var first = true
    for (element in this) {
        if (!first) buffer.append(separator)
        buffer.append(transform(element).toString())
        first = false
    }
    buffer.append(postfix)
    return buffer.toString()
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
): String = joinToString(", ", "", "", transform)

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
