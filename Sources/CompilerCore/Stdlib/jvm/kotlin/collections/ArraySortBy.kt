@file:kotlin.jvm.JvmName("ArraysKt")

package kotlin.collections

public inline fun <T, R : Comparable<R>> Array<out T>.sortBy(crossinline selector: (T) -> R?) {
    @Suppress("UNCHECKED_CAST")
    val array = this as Array<T>
    java.util.Arrays.sort<T>(array, 0, array.size, object : java.util.Comparator<T> {
        override fun compare(first: T, second: T): Int {
            val firstKey = selector(first)
            val secondKey = selector(second)
            if (firstKey == null) return if (secondKey == null) 0 else -1
            if (secondKey == null) return 1
            return firstKey.compareTo(secondKey)
        }
    })
}

public inline fun <T, R : Comparable<R>> Array<out T>.sortedByDescending(crossinline selector: (T) -> R?): List<T> {
    @Suppress("UNCHECKED_CAST")
    val result = java.util.Arrays.copyOf(this, size) as Array<T>
    java.util.Arrays.sort<T>(result, 0, result.size, object : java.util.Comparator<T> {
        override fun compare(first: T, second: T): Int {
            val firstKey = selector(first)
            val secondKey = selector(second)
            if (firstKey == null) return if (secondKey == null) 0 else 1
            if (secondKey == null) return -1
            return secondKey.compareTo(firstKey)
        }
    })
    val sorted = java.util.ArrayList<T>(result.size)
    for (element in result) sorted.add(element)
    return sorted
}
