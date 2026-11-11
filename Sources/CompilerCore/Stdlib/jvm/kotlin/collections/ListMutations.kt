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
