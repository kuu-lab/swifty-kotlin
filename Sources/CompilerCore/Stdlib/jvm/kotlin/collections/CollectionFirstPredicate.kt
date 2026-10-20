@file:kotlin.jvm.JvmName("CollectionsKt")
package kotlin.collections

public inline fun <T> Iterable<T>.first(predicate: (T) -> Boolean): T {
    for (element in this) if (predicate(element)) return element
    throw NoSuchElementException("Collection contains no element matching the predicate.")
}
