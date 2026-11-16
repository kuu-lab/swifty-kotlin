package kotlin.collections

external fun <T> Array<out T>.indexOf(element: T): Int
external fun <T> Array<out T>.lastIndexOf(element: T): Int

inline fun <T> Array<out T>.first(predicate: (T) -> Boolean): T {
    for (element in this) if (predicate(element)) return element
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

inline fun CharArray.any(predicate: (Char) -> Boolean): Boolean {
    for (element in this) if (predicate(element)) return true
    return false
}
