package kotlin.collections

@Suppress("UNCHECKED_CAST")
public inline fun <T> Iterable<T>.last(predicate: (T) -> Boolean): T {
    var last: T? = null
    var found = false
    for (element in this) {
        if (predicate(element)) {
            last = element
            found = true
        }
    }
    if (!found) throw NoSuchElementException("Collection contains no element matching the predicate.")
    return last as T
}

public inline fun <T> List<T>.last(predicate: (T) -> Boolean): T {
    val cursor = listIterator(size)
    while (cursor.hasPrevious()) {
        val element = cursor.previous()
        if (predicate(element)) return element
    }
    throw NoSuchElementException("Collection contains no element matching the predicate.")
}
