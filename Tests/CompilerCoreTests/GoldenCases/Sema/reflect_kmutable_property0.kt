package golden.sema

import kotlin.reflect.KMutableProperty0

// STDLIB-REFLECT-TYPE-010: KMutableProperty0 represents a mutable zero-receiver property reference.

fun <V> assignTo(prop: KMutableProperty0<V>, value: V) {
    prop.set(value)
}

fun readFrom(prop: KMutableProperty0<Int>): Int {
    return prop.get()
}

fun swap(prop: KMutableProperty0<String>, newValue: String): String {
    val old = prop.get()
    prop.set(newValue)
    return old
}
