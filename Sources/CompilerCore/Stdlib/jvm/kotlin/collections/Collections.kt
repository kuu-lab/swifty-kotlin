package kotlin.collections

import kotlin.jvm.internal.__jvmCopyList
import kotlin.jvm.internal.__jvmReverseOrder
import kotlin.jvm.internal.__jvmSortListWithComparator
import kotlin.jvm.internal.__jvmSortList
import kotlin.jvm.internal.__jvmNewArrayList
import kotlin.jvm.internal.__jvmNewList
import kotlin.jvm.internal.__jvmSingletonList
import kotlin.jvm.internal.__jvmArrayList

public fun <T> emptyList(): List<T> = RepositoryEmptyList as List<T>
public fun <T> listOf(element: T): List<T> = __jvmSingletonList(element)
public fun <T> listOf(vararg elements: T): List<T> {
    if (elements.size == 0) return emptyList<T>()
    return __jvmArrayList(elements)
}
public fun <T> mutableListOf(vararg elements: T): MutableList<T> {
    val result = __jvmNewList<T>()
    for (element in elements) result.add(element)
    return result
}


// Official Kotlin consumers select this Collection receiver overload.
public fun <T> Collection<T>.toMutableList(): MutableList<T> = __jvmCopyList(this)

public fun <T> Iterable<T>.toMutableList(): MutableList<T> {
    if (this is Collection<*>) return __jvmCopyList(this as Collection<T>)
    val result = mutableListOf<T>()
    for (element in this) result.add(element)
    return result
}
public fun <T> Iterable<T>.toList(): List<T> {
    if (this is Collection<*>) {
        if (this.size == 0) return emptyList<T>()
        if (this.size == 1) {
            val element = if (this is List<*>) this[0] as T else this.iterator().next()
            return listOf(element)
        }
    }
    val result = this.toMutableList()
    if (this is Collection<*>) return result
    if (result.size == 0) return emptyList<T>()
    if (result.size == 1) return listOf(result[0])
    return result
}
public fun <T> Iterable<T>.toMutableSet(): MutableSet<T> {
    val result = mutableSetOf<T>()
    for (element in this) result.add(element)
    return result
}
public fun <T> Iterable<T>.toSet(): Set<T> {
    if (this is Collection<*>) {
        if (this.size == 0) return emptySet<T>()
        if (this.size == 1) {
            val element = if (this is List<*>) this[0] as T else this.iterator().next()
            return setOf(element)
        }
    }
    val result = this.toMutableSet()
    if (this is Collection<*>) return result
    if (result.size == 0) return emptySet<T>()
    if (result.size == 1) return setOf(result.iterator().next())
    return result
}
public fun <T> Iterable<T>.distinct(): List<T> = this.toMutableSet().toList()
private fun <T> reverseInPlace(list: MutableList<T>) {
    var left = 0
    var right = list.size - 1
    while (left < right) {
        val saved = list[left]
        list[left] = list[right]
        list[right] = saved
        left++; right--
    }
}
public fun <T> Iterable<T>.reversed(): List<T> {
    val original: Iterable<T> = this
    if (this is Collection<*> && this.size <= 1) return original.toList()
    val result = this.toMutableList()
    reverseInPlace(result)
    return result
}
public fun <T: Comparable<T>> Iterable<T>.sorted(): List<T> {
    val original: Iterable<T> = this
    if (this is Collection<*> && this.size <= 1) return original.toList()
    val result = this.toMutableList()
    __jvmSortList(result)
    return result
}
public fun <T: Comparable<T>> Iterable<T>.sortedDescending(): List<T> {
    val original: Iterable<T> = this
    if (this is Collection<*> && this.size <= 1) return original.toList()
    val result = this.toMutableList()
    __jvmSortListWithComparator(result, __jvmReverseOrder())
    return result
}
public fun <T> Iterable<T>.take(n: Int): List<T> {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    if (n == 0) return emptyList<T>()
    val result = mutableListOf<T>()
    var remaining = n
    for (element in this) {
        result.add(element)
        remaining--
        if (remaining == 0) break
    }
    if (result.size == 0) return emptyList<T>()
    if (result.size == 1) return listOf(result[0])
    return result
}
public fun <T> Iterable<T>.drop(n: Int): List<T> {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    val result = mutableListOf<T>()
    var remaining = n
    for (element in this) {
        if (remaining == 0) result.add(element) else remaining--
    }
    if (result.size == 0) return emptyList<T>()
    if (result.size == 1) return listOf(result[0])
    return result
}
public fun <T> Iterable<T>.joinToString(separator: CharSequence = ", ", prefix: CharSequence = "", postfix: CharSequence = "", limit: Int = -1, truncated: CharSequence = "...", transform: ((T) -> CharSequence)? = null): String {
    val result = StringBuilder()
    result.append(prefix)
    var count = 0
    for (element in this) {
        count++
        if (count > 1) result.append(separator)
        if (limit >= 0 && count > limit) break
        if (transform != null) result.append(transform(element))
        else if (element is CharSequence) result.append(element)
        else result.append(element)
    }
    if (limit >= 0 && count > limit) result.append(truncated)
    result.append(postfix)
    return result.toString()
}

public fun <T> Iterable<T>.asSequence(): kotlin.sequences.Sequence<T> {
    val source = this
    return object: kotlin.sequences.Sequence<T> {
        override fun iterator(): Iterator<T> = source.iterator()
    }
}

public fun <T> Iterable<T>.first(): T {
    if (this is List<*>) return (this as List<T>).first()
    val iterator = this.iterator()
    if (!iterator.hasNext()) throw NoSuchElementException("Collection is empty.")
    return iterator.next()
}

public fun <T> List<T>.first(): T {
    if (this.isEmpty()) throw NoSuchElementException("List is empty.")
    return this[0]
}

public fun <T> Iterable<T>.last(): T {
    if (this is List<*>) return (this as List<T>).last()
    val iterator = this.iterator()
    if (!iterator.hasNext()) throw NoSuchElementException("Collection is empty.")
    var result = iterator.next()
    while (iterator.hasNext()) result = iterator.next()
    return result
}

public fun <T> List<T>.last(): T {
    if (this.isEmpty()) throw NoSuchElementException("List is empty.")
    return this[this.size - 1]
}

public fun <T> Iterable<T>.firstOrNull(): T? {
    if (this is List<*>) return (this as List<T>).firstOrNull()
    val iterator = this.iterator()
    if (!iterator.hasNext()) return null
    return iterator.next()
}

public fun <T> List<T>.firstOrNull(): T? = if (this.isEmpty()) null else this[0]

public fun <T> Iterable<T>.lastOrNull(): T? {
    if (this is List<*>) return (this as List<T>).lastOrNull()
    val iterator = this.iterator()
    if (!iterator.hasNext()) return null
    var result = iterator.next()
    while (iterator.hasNext()) result = iterator.next()
    return result
}

public fun <T> List<T>.lastOrNull(): T? = if (this.isEmpty()) null else this[this.size - 1]

fun <T> collectionSizeOrDefault(value: Iterable<T>, defaultValue: Int): Int = if (value is Collection<*>) value.size else defaultValue
fun <T> collectionSizeOrNull(value: Iterable<T>): Int? = if (value is Collection<*>) value.size else null
fun <T> Iterable<T>.sortedWith(comparator: Comparator<in T>): List<T> {
    val result = this.toMutableList()
    __jvmSortListWithComparator(result, comparator)
    return result
}
fun <T> MutableCollection<in T>.addAll(elements: Iterable<T>): Boolean {
    var changed = false
    for (element in elements) if (this.add(element)) changed = true
    return changed
}

public fun <T> arrayListOf(vararg elements: T): java.util.ArrayList<T> {
    val result = __jvmNewArrayList<T>()
    for (element in elements) result.add(element)
    return result
}

public operator fun <T> Collection<T>.plus(element: T): List<T> {
    val result = mutableListOf<T>()
    for (item in this) result.add(item)
    result.add(element)
    return result
}
public operator fun <T> Iterable<T>.plus(element: T): List<T> {
    val result = mutableListOf<T>()
    for (item in this) result.add(item)
    result.add(element)
    return result
}
public operator fun <T> Collection<T>.plus(elements: Iterable<T>): List<T> {
    val result = mutableListOf<T>()
    for (item in this) result.add(item)
    for (item in elements) result.add(item)
    return result
}
public operator fun <T> Iterable<T>.plus(elements: Iterable<T>): List<T> {
    val result = mutableListOf<T>()
    for (item in this) result.add(item)
    for (item in elements) result.add(item)
    return result
}
public operator fun <T> Iterable<T>.minus(element: T): List<T> {
    val result = mutableListOf<T>()
    var removed = false
    for (item in this) {
        if (!removed && item == element) removed = true else result.add(item)
    }
    return result
}
public operator fun <T> Iterable<T>.minus(elements: Iterable<T>): List<T> {
    val removed = if (elements is Collection<*>) elements as Collection<T> else elements.toList()
    val result = mutableListOf<T>()
    for (item in this) if (!removed.contains(item)) result.add(item)
    return result
}

public operator fun <T> Collection<T>.plus(elements: Array<out T>): List<T> {
    val result = mutableListOf<T>()
    for (item in this) result.add(item)
    for (item in elements) result.add(item)
    return result
}
public operator fun <T> Iterable<T>.plus(elements: Array<out T>): List<T> {
    val result = mutableListOf<T>()
    for (item in this) result.add(item)
    for (item in elements) result.add(item)
    return result
}
public operator fun <T> Iterable<T>.minus(elements: Array<out T>): List<T> {
    val result = mutableListOf<T>()
    for (item in this) {
        var removed = false
        for (element in elements) if (item == element) { removed = true; break }
        if (!removed) result.add(item)
    }
    return result
}

public operator fun <T> Collection<T>.plus(elements: kotlin.sequences.Sequence<T>): List<T> {
    val result = mutableListOf<T>()
    for (item in this) result.add(item)
    for (item in elements) result.add(item)
    return result
}
public operator fun <T> Iterable<T>.plus(elements: kotlin.sequences.Sequence<T>): List<T> {
    val result = mutableListOf<T>()
    for (item in this) result.add(item)
    for (item in elements) result.add(item)
    return result
}
public operator fun <T> Iterable<T>.minus(elements: kotlin.sequences.Sequence<T>): List<T> {
    val removed = mutableListOf<T>()
    for (item in elements) removed.add(item)
    val result = mutableListOf<T>()
    for (item in this) if (!removed.contains(item)) result.add(item)
    return result
}
