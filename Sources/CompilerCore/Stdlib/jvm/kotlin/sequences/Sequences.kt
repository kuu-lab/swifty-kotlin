package kotlin.sequences

import kotlin.jvm.internal.__jvmMinDouble
import kotlin.jvm.internal.__jvmMaxDouble
import kotlin.jvm.internal.__jvmMinFloat
import kotlin.jvm.internal.__jvmMaxFloat
import kotlin.jvm.internal.__jvmAtomicFlag
import kotlin.jvm.internal.__jvmCompareFlag

private object EmptySequence: Sequence<Any?> {
    override fun iterator(): Iterator<Any?> = object: Iterator<Any?> {
        override fun hasNext(): Boolean = false
        override fun next(): Any? = throw NoSuchElementException()
    }
}
public fun <T> emptySequence(): Sequence<T> = EmptySequence as Sequence<T>
public fun <T> sequenceOf(element: T): Sequence<T> = listOf(element).asSequence()
public fun <T> sequenceOf(vararg elements: T): Sequence<T> = object: Sequence<T> {
    override fun iterator(): Iterator<T> = object: Iterator<T> {
        var index = 0
        override fun hasNext(): Boolean = index < elements.size
        override fun next(): T {
            if (!hasNext()) throw NoSuchElementException()
            val element = elements[index]
            index++
            return element
        }
    }
}

private class GeneratorSequence<T: Any>(val seed: () -> T?, val advance: (T) -> T?): Sequence<T> {
    override fun iterator(): Iterator<T> = object: Iterator<T> {
        var state = -2
        var item: T? = null
        fun calculateNext() {
            item = if (state == -2) seed() else advance(item!!)
            state = if (item == null) 0 else 1
        }
        override fun hasNext(): Boolean {
            if (state < 0) calculateNext()
            return state == 1
        }
        override fun next(): T {
            if (state < 0) calculateNext()
            if (state == 0) throw NoSuchElementException()
            val result = item!!
            state = -1
            return result
        }
    }
}
@kotlin.internal.LowPriorityInOverloadResolution
public fun <T: Any> generateSequence(seed: T?, nextFunction: (T) -> T?): Sequence<T> = GeneratorSequence({ seed }, nextFunction)
public fun <T: Any> generateSequence(seedFunction: () -> T?, nextFunction: (T) -> T?): Sequence<T> = GeneratorSequence(seedFunction, nextFunction)
public fun <T: Any> generateSequence(nextFunction: () -> T?): Sequence<T> = GeneratorSequence(nextFunction, { nextFunction() }).constrainOnce()

public fun <T> Iterator<T>.asSequence(): Sequence<T> {
    val source = this
    return object: Sequence<T> {
        override fun iterator(): Iterator<T> = source
    }.constrainOnce()
}
public fun <T> Sequence<T>.asIterable(): Iterable<T> {
    val source = this
    return object: Iterable<T> {
        override fun iterator(): Iterator<T> = source.iterator()
    }
}
public fun <T> Sequence<T>.constrainOnce(): Sequence<T> {
    val source = this
    val used = __jvmAtomicFlag()
    return object: Sequence<T> {
        override fun iterator(): Iterator<T> {
            if (!__jvmCompareFlag(used, false, true)) throw IllegalStateException("This sequence can be consumed only once.")
            return source.iterator()
        }
    }
}

public operator fun <T> Sequence<T>.plus(element: T): Sequence<T> = this.plus(sequenceOf(element))
public operator fun <T> Sequence<T>.plus(elements: Array<out T>): Sequence<T> = this.plus(elements.asSequence())
public operator fun <T> Sequence<T>.plus(elements: Iterable<T>): Sequence<T> = this.plus(elements.asSequence())
public operator fun <T> Sequence<T>.plus(elements: Sequence<T>): Sequence<T> {
    val first = this
    return object: Sequence<T> {
        override fun iterator(): Iterator<T> = object: Iterator<T> {
            var iterator = first.iterator()
            var consumedFirst = false
            override fun hasNext(): Boolean {
                if (!consumedFirst && !iterator.hasNext()) {
                    iterator = elements.iterator()
                    consumedFirst = true
                }
                return iterator.hasNext()
            }
            override fun next(): T {
                if (!hasNext()) throw NoSuchElementException()
                return iterator.next()
            }
        }
    }
}

public fun <T> Sequence<T>.toMutableList(): MutableList<T> {
    val result = mutableListOf<T>()
    for (element in this) result.add(element)
    return result
}
public fun <T> Sequence<T>.toList(): List<T> = this.toMutableList().toList()
public fun <T> Sequence<T>.toMutableSet(): MutableSet<T> {
    val result = mutableSetOf<T>()
    for (element in this) result.add(element)
    return result
}
public fun <T> Sequence<T>.toSet(): Set<T> {
    val result = this.toMutableSet()
    if (result.size == 0) return emptySet<T>()
    if (result.size == 1) return setOf(result.iterator().next())
    return result
}
public fun <T> Sequence<T>.count(): Int {
    var count = 0
    for (element in this) {
        count++
        if (count < 0) throw ArithmeticException("Count overflow has happened.")
    }
    return count
}
public fun <T> Sequence<T>.any(): Boolean = this.iterator().hasNext()
public fun <T> Sequence<T>.none(): Boolean = !this.iterator().hasNext()
public fun <T> Sequence<T>.first(): T {
    val iterator = this.iterator()
    if (!iterator.hasNext()) throw NoSuchElementException("Sequence is empty.")
    return iterator.next()
}
public fun <T> Sequence<T>.firstOrNull(): T? {
    val iterator = this.iterator()
    return if (iterator.hasNext()) iterator.next() else null
}
public fun <T> Sequence<T>.last(): T {
    val iterator = this.iterator()
    if (!iterator.hasNext()) throw NoSuchElementException("Sequence is empty.")
    var result = iterator.next()
    while (iterator.hasNext()) result = iterator.next()
    return result
}
public fun <T> Sequence<T>.lastOrNull(): T? {
    val iterator = this.iterator()
    if (!iterator.hasNext()) return null
    var result = iterator.next()
    while (iterator.hasNext()) result = iterator.next()
    return result
}
public fun <T> Sequence<T>.single(): T {
    val iterator = this.iterator()
    if (!iterator.hasNext()) throw NoSuchElementException("Sequence is empty.")
    val result = iterator.next()
    if (iterator.hasNext()) throw IllegalArgumentException("Sequence has more than one element.")
    return result
}
public fun <T> Sequence<T>.singleOrNull(): T? {
    val iterator = this.iterator()
    if (!iterator.hasNext()) return null
    val result = iterator.next()
    return if (iterator.hasNext()) null else result
}
public fun <T> Sequence<T>.elementAt(index: Int): T {
    if (index < 0) throw IndexOutOfBoundsException("Sequence doesn't contain element at index $index.")
    var position = 0
    for (element in this) {
        if (position == index) return element
        position++
    }
    throw IndexOutOfBoundsException("Sequence doesn't contain element at index $index.")
}
public fun <T> Sequence<T>.elementAtOrNull(index: Int): T? {
    if (index < 0) return null
    var position = 0
    for (element in this) { if (position == index) return element; position++ }
    return null
}
public operator fun <T> Sequence<T>.contains(element: T): Boolean {
    for (candidate in this) if (candidate == element) return true
    return false
}
public fun <T> Sequence<T>.joinToString(separator: CharSequence = ", ", prefix: CharSequence = "", postfix: CharSequence = "", limit: Int = -1, truncated: CharSequence = "...", transform: ((T) -> CharSequence)? = null): String = this.asIterable().joinToString(separator, prefix, postfix, limit, truncated, transform)
public fun <T: Comparable<T>> Sequence<T>.minOrNull(): T? {
    val iterator = this.iterator()
    if (!iterator.hasNext()) return null
    var result = iterator.next()
    while (iterator.hasNext()) { val element = iterator.next(); if (result.compareTo(element) > 0) result = element }
    return result
}
public fun <T: Comparable<T>> Sequence<T>.maxOrNull(): T? {
    val iterator = this.iterator()
    if (!iterator.hasNext()) return null
    var result = iterator.next()
    while (iterator.hasNext()) { val element = iterator.next(); if (result.compareTo(element) < 0) result = element }
    return result
}

public fun Sequence<Double>.minOrNull(): Double? {
    val iterator = this.iterator()
    if (!iterator.hasNext()) return null
    var result = iterator.next()
    while (iterator.hasNext()) result = __jvmMinDouble(result, iterator.next())
    return result
}

public fun Sequence<Double>.maxOrNull(): Double? {
    val iterator = this.iterator()
    if (!iterator.hasNext()) return null
    var result = iterator.next()
    while (iterator.hasNext()) result = __jvmMaxDouble(result, iterator.next())
    return result
}

public fun Sequence<Float>.minOrNull(): Float? {
    val iterator = this.iterator()
    if (!iterator.hasNext()) return null
    var result = iterator.next()
    while (iterator.hasNext()) result = __jvmMinFloat(result, iterator.next())
    return result
}

public fun Sequence<Float>.maxOrNull(): Float? {
    val iterator = this.iterator()
    if (!iterator.hasNext()) return null
    var result = iterator.next()
    while (iterator.hasNext()) result = __jvmMaxFloat(result, iterator.next())
    return result
}
