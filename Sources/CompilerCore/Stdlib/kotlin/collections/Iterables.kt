package kotlin.collections

// KSP-435
// Generic Iterable<T> surface migrated from the Swift runtime `kk_iterable_*`
// bridges. Every implementation only relies on `iterator()` virtual dispatch,
// so it works for List, Set and any user-defined Iterable alike.

public fun <T> Iterable<T>.toList(): List<T> {
    val result = mutableListOf<T>()
    val iterator = iterator()
    while (iterator.hasNext()) result.add(iterator.next())
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

public fun <T> Iterable<T>.joinToString(
    transform: (T) -> Any
): String = joinToString(", ", "", "", transform)
