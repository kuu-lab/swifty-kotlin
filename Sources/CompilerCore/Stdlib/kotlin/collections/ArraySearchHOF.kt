package kotlin.collections

import kotlin.internal.__valuesEqual

// MIGRATION-COL-006
// Array search helpers.
// Migration source: Sources/Runtime/RuntimeCollectionHOFArray.swift (kk_array_*)
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
