package kotlin.collections

import kotlin.internal.__valuesEqual

// MIGRATION-COL-006
// Array search helpers. Generic and primitive-array variants are source-backed.
//
// Equality is delegated to __kk_values_equal via kotlin.internal.__valuesEqual.

public operator fun <T> Array<T>.contains(element: T): Boolean {
    var i = 0
    val sz = this.size
    while (i < sz) {
        if (__valuesEqual(this[i], element)) return true
        i++
    }
    return false
}

public fun <T> Array<T>.indexOf(element: T): Int {
    var i = 0
    val sz = this.size
    while (i < sz) {
        if (__valuesEqual(this[i], element)) return i
        i++
    }
    return -1
}

public fun <T> Array<T>.lastIndexOf(element: T): Int {
    var i = this.size - 1
    while (i >= 0) {
        if (__valuesEqual(this[i], element)) return i
        i--
    }
    return -1
}

// KSP-433: predicate-based search / quantifier HOFs are source-backed.
// Exception messages match kotlinc's Array wording
// ("Array is empty." / "Array contains no element matching the predicate.").

public fun <T> Array<T>.find(predicate: (T) -> Boolean): T? {
    var i = 0
    val sz = this.size
    while (i < sz) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun <T> Array<T>.findLast(predicate: (T) -> Boolean): T? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun <T> Array<T>.first(): T {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[0]
}

public fun <T> Array<T>.first(predicate: (T) -> Boolean): T {
    var i = 0
    val sz = this.size
    while (i < sz) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun <T> Array<T>.firstOrNull(): T? {
    if (this.size == 0) return null
    return this[0]
}

public fun <T> Array<T>.firstOrNull(predicate: (T) -> Boolean): T? {
    var i = 0
    val sz = this.size
    while (i < sz) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun <T> Array<T>.last(): T {
    if (this.size == 0) throw NoSuchElementException("Array is empty.")
    return this[this.size - 1]
}

public fun <T> Array<T>.last(predicate: (T) -> Boolean): T {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    throw NoSuchElementException("Array contains no element matching the predicate.")
}

public fun <T> Array<T>.lastOrNull(): T? {
    if (this.size == 0) return null
    return this[this.size - 1]
}

public fun <T> Array<T>.lastOrNull(predicate: (T) -> Boolean): T? {
    var i = this.size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun <T> Array<T>.any(): Boolean = this.size != 0

public fun <T> Array<T>.any(predicate: (T) -> Boolean): Boolean {
    var i = 0
    val sz = this.size
    while (i < sz) {
        if (predicate(this[i])) return true
        i++
    }
    return false
}

public fun <T> Array<T>.all(predicate: (T) -> Boolean): Boolean {
    var i = 0
    val sz = this.size
    while (i < sz) {
        if (!predicate(this[i])) return false
        i++
    }
    return true
}

public fun <T> Array<T>.none(): Boolean = this.size == 0

public fun <T> Array<T>.none(predicate: (T) -> Boolean): Boolean {
    var i = 0
    val sz = this.size
    while (i < sz) {
        if (predicate(this[i])) return false
        i++
    }
    return true
}

public fun <T> Array<T>.count(): Int = this.size

public fun <T> Array<T>.count(predicate: (T) -> Boolean): Int {
    var count = 0
    var i = 0
    val sz = this.size
    while (i < sz) {
        if (predicate(this[i])) count++
        i++
    }
    return count
}
