package kotlin.collections

import kotlin.jvm.internal.__jvmAddAllCollection
import kotlin.jvm.internal.__jvmRemoveAllCollection
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

public fun Collection<*>.indices(): IntRange = 0..this.size - 1
public fun <T> List<T>.indices(): IntRange = 0..this.size - 1
public fun <T> List<T>.lastIndex(): Int = this.size - 1

public operator fun <T> List<T>.component1(): T = this[0]
public operator fun <T> List<T>.component2(): T = this[1]
public operator fun <T> List<T>.component3(): T = this[2]
public operator fun <T> List<T>.component4(): T = this[3]
public operator fun <T> List<T>.component5(): T = this[4]

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
public fun <T> List<T>.takeLast(n: Int): List<T> {
    if (n < 0) throw IllegalArgumentException("Requested element count $n is less than zero.")
    if (n == 0) return emptyList<T>()
    val values = this.toList()
    val start = if (n >= values.size) 0 else values.size - n
    if (start == 0) return values
    val result = mutableListOf<T>()
    var index = start
    while (index < values.size) {
        result.add(values[index])
        index++
    }
    return result
}
public inline fun <T> Iterable<T>.takeWhile(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        if (!predicate(element)) break
        result.add(element)
    }
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
public inline fun <T> Iterable<T>.dropWhile(predicate: (T) -> Boolean): List<T> {
    var dropping = true
    val result = mutableListOf<T>()
    for (element in this) {
        if (dropping && predicate(element)) continue
        dropping = false
        result.add(element)
    }
    return result
}
public fun <T> List<T>.dropLastWhile(predicate: (T) -> Boolean): List<T> {
    var end = size
    while (end > 0 && predicate(this[end - 1])) end--
    if (end == 0) return emptyList<T>()
    val result = mutableListOf<T>()
    var index = 0
    while (index < end) {
        result.add(this[index])
        index++
    }
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

public fun <T> Iterable<T>.elementAt(index: Int): T {
    if (this is List<*>) {
        if (index < 0 || index >= this.size) {
            throw IndexOutOfBoundsException("Index $index out of bounds for length ${this.size}")
        }
        return this[index] as T
    }
    return elementAtOrElse(index) {
        throw IndexOutOfBoundsException("Collection doesn't contain element at index $index.")
    }
}

public fun <T> Iterable<T>.elementAtOrElse(index: Int, defaultValue: (Int) -> T): T {
    if (this is List<*>) {
        if (index >= 0 && index < this.size) return this[index] as T
        return defaultValue(index)
    }
    if (index < 0) return defaultValue(index)
    val iterator = iterator()
    var count = 0
    while (iterator.hasNext()) {
        val element = iterator.next()
        if (index == count++) return element
    }
    return defaultValue(index)
}

public fun <T> Iterable<T>.elementAtOrNull(index: Int): T? {
    if (this is List<*>) {
        if (index >= 0 && index < this.size) return this[index] as T
        return null
    }
    if (index < 0) return null
    val iterator = iterator()
    var count = 0
    while (iterator.hasNext()) {
        val element = iterator.next()
        if (index == count++) return element
    }
    return null
}

public fun <T> Iterable<T>.single(): T {
    if (this is List<*>) return (this as List<T>).single()
    val iterator = iterator()
    if (!iterator.hasNext()) throw NoSuchElementException("Collection is empty.")
    val result = iterator.next()
    if (iterator.hasNext()) throw IllegalArgumentException("Collection has more than one element.")
    return result
}

public fun <T> List<T>.single(): T {
    if (this.size == 1) return this[0]
    if (this.size == 0) throw NoSuchElementException("Collection is empty.")
    throw IllegalArgumentException("Collection has more than one element.")
}

public inline fun <T> Iterable<T>.single(predicate: (T) -> Boolean): T {
    if (this is List<*>) return (this as List<T>).single(predicate)
    var result: T? = null
    var found = false
    for (element in this) {
        if (predicate(element)) {
            if (found) throw IllegalArgumentException("Collection contains more than one matching element.")
            result = element
            found = true
        }
    }
    if (!found) throw NoSuchElementException("Collection contains no element matching the predicate.")
    @Suppress("UNCHECKED_CAST")
    return result as T
}

public inline fun <T> List<T>.single(predicate: (T) -> Boolean): T {
    var result: T? = null
    var found = false
    for (element in this) {
        if (predicate(element)) {
            if (found) throw IllegalArgumentException("Collection contains more than one matching element.")
            result = element
            found = true
        }
    }
    if (!found) throw NoSuchElementException("Collection contains no element matching the predicate.")
    @Suppress("UNCHECKED_CAST")
    return result as T
}

public fun <T> Iterable<T>.singleOrNull(): T? {
    if (this is List<*>) return (this as List<T>).singleOrNull()
    val iterator = iterator()
    if (!iterator.hasNext()) return null
    val result = iterator.next()
    if (iterator.hasNext()) return null
    return result
}

public fun <T> List<T>.singleOrNull(): T? = if (this.size == 1) this[0] else null

public inline fun <T> Iterable<T>.singleOrNull(predicate: (T) -> Boolean): T? {
    if (this is List<*>) return (this as List<T>).singleOrNull(predicate)
    var result: T? = null
    var found = false
    for (element in this) {
        if (predicate(element)) {
            if (found) return null
            result = element
            found = true
        }
    }
    return if (found) result else null
}

public inline fun <T> List<T>.singleOrNull(predicate: (T) -> Boolean): T? {
    var result: T? = null
    var found = false
    for (element in this) {
        if (predicate(element)) {
            if (found) return null
            result = element
            found = true
        }
    }
    return if (found) result else null
}

fun <T> collectionSizeOrDefault(value: Iterable<T>, defaultValue: Int): Int = if (value is Collection<*>) value.size else defaultValue
fun <T> collectionSizeOrNull(value: Iterable<T>): Int? = if (value is Collection<*>) value.size else null
fun <T> Iterable<T>.sortedWith(comparator: Comparator<in T>): List<T> {
    val result = this.toMutableList()
    __jvmSortListWithComparator(result, comparator)
    return result
}
fun <T> MutableCollection<in T>.addAll(elements: Iterable<T>): Boolean {
    if (elements is Collection<*>) return __jvmAddAllCollection(this, elements as Collection<T>)
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
    val result = this.toMutableList()
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
    val result = this.toMutableList()
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
    val result = this.toMutableList()
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
    val result = this.toMutableList()
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

public fun <T> MutableCollection<in T>.addAll(elements: Array<out T>): Boolean = __jvmAddAllCollection(this, __jvmArrayList(elements))
public fun <T> MutableCollection<in T>.addAll(elements: kotlin.sequences.Sequence<T>): Boolean {
    var changed = false
    for (element in elements) if (this.add(element)) changed = true
    return changed
}
public fun <T> MutableCollection<in T>.removeAll(elements: Iterable<T>): Boolean {
    val removed = if (elements is Collection<*>) elements as Collection<T> else elements.toList()
    return __jvmRemoveAllCollection(this, removed)
}
public fun <T> MutableCollection<in T>.removeAll(elements: Array<out T>): Boolean {
    if (elements.size == 0) return false
    return __jvmRemoveAllCollection(this, __jvmArrayList(elements))
}
public fun <T> MutableCollection<in T>.removeAll(elements: kotlin.sequences.Sequence<T>): Boolean {
    val removed = elements.toList()
    return !removed.isEmpty() && __jvmRemoveAllCollection(this, removed)
}
