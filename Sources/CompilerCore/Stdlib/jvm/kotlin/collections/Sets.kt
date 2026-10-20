package kotlin.collections

import kotlin.jvm.internal.__jvmNewSet
import kotlin.jvm.internal.__jvmSingletonSet

public fun <T> emptySet(): Set<T> = RepositoryEmptySet as Set<T>
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
