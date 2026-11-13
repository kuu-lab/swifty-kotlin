@file:kotlin.jvm.JvmName("CollectionsKt")

package kotlin.collections

public fun <T> MutableList<T>.sortWith(comparator: Comparator<in T>) {
    if (size > 1) java.util.Collections.sort<T>(this, comparator as java.util.Comparator<T>)
}

public fun <T> MutableList<T>.removeFirst(): T {
    if (isEmpty()) throw NoSuchElementException("List is empty.")
    return removeAt(0)
}

public fun <T> MutableList<T>.removeLast(): T {
    if (isEmpty()) throw NoSuchElementException("List is empty.")
    return removeAt(size - 1)
}

// Preserve Kotlin's function-type API for JVM MutableList receivers.
public fun <T> MutableList<T>.replaceAll(transform: (T) -> T) {
    var index = 0
    while (index < size) {
        this[index] = transform(this[index])
        index += 1
    }
}

public fun <T> MutableList<T>.removeFirstOrNull(): T? = if (isEmpty()) null else removeAt(0)

public fun <T> MutableList<T>.removeLastOrNull(): T? = if (isEmpty()) null else removeAt(size - 1)
