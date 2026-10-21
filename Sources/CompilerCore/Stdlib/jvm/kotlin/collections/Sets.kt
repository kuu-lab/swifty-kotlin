package kotlin.collections

import kotlin.jvm.internal.__jvmCopySet
import kotlin.jvm.internal.__jvmArrayList
import kotlin.jvm.internal.__jvmRemoveAllCollection
import kotlin.jvm.internal.__jvmNewSet
import kotlin.jvm.internal.__jvmSingletonSet

public fun <T> emptySet(): Set<T> = EmptySet as Set<T>
public fun <T> setOf(element: T): Set<T> = __jvmSingletonSet(element)
public fun <T> setOf(vararg elements: T): Set<T> {
    if (elements.size == 0) return emptySet<T>()
    if (elements.size == 1) return setOf(elements[0])
    val result = __jvmNewSet<T>()
    for (element in elements) result.add(element)
    return result
}
public fun <T> mutableSetOf(vararg elements: T): MutableSet<T> {
    val result = __jvmNewSet<T>()
    for (element in elements) result.add(element)
    return result
}

public operator fun <T> Set<T>.plus(element: T): Set<T> {
    val result = mutableSetOf<T>()
    for (item in this) result.add(item)
    result.add(element)
    return result
}
public operator fun <T> Set<T>.plus(elements: Iterable<T>): Set<T> {
    val result = mutableSetOf<T>()
    for (item in this) result.add(item)
    for (item in elements) result.add(item)
    return result
}
public operator fun <T> Set<T>.minus(element: T): Set<T> {
    val result = mutableSetOf<T>()
    var removed = false
    for (item in this) {
        if (!removed && item == element) removed = true else result.add(item)
    }
    return result
}
public operator fun <T> Set<T>.minus(elements: Iterable<T>): Set<T> {
    val removed = if (elements is Collection<*>) elements as Collection<T> else elements.toList()
    if (removed.isEmpty()) return this.toSet()
    if (removed is Set<*>) {
        val membership = removed as Set<T>
        val result = mutableSetOf<T>()
        for (item in this) if (!membership.contains(item)) result.add(item)
        return result
    }
    val result = __jvmCopySet(this)
    __jvmRemoveAllCollection(result, removed)
    return result
}

public operator fun <T> Set<T>.plus(elements: Array<out T>): Set<T> {
    val result = mutableSetOf<T>()
    for (item in this) result.add(item)
    for (item in elements) result.add(item)
    return result
}
public operator fun <T> Set<T>.minus(elements: Array<out T>): Set<T> {
    val result = __jvmCopySet(this)
    if (elements.size != 0) __jvmRemoveAllCollection(result, __jvmArrayList(elements))
    return result
}

public operator fun <T> Set<T>.plus(elements: kotlin.sequences.Sequence<T>): Set<T> {
    val result = mutableSetOf<T>()
    for (item in this) result.add(item)
    for (item in elements) result.add(item)
    return result
}
public operator fun <T> Set<T>.minus(elements: kotlin.sequences.Sequence<T>): Set<T> {
    val result = __jvmCopySet(this)
    val removed = elements.toList()
    if (!removed.isEmpty()) __jvmRemoveAllCollection(result, removed)
    return result
}
