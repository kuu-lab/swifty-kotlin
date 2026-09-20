/*
 * KSP-1084: Kotlin source-backed field operations for receiverless mutable
 * property references.
 *
 * Kotlin/Native implements these declarations as field intrinsics. KSwiftK
 * has no corresponding intrinsic or runtime bridge, so keep the API source
 * backed and express its sequential observable operations through get/set.
 */

package kotlin.concurrent

import kotlin.reflect.KMutableProperty0

@PublishedApi
internal fun <T> KMutableProperty0<T>.atomicGetField(): T = get()

@PublishedApi
internal fun <T> KMutableProperty0<T>.atomicSetField(newValue: T) {
    set(newValue)
}

@PublishedApi
internal fun <T> KMutableProperty0<T>.compareAndSetField(expectedValue: T, newValue: T): Boolean {
    val oldValue = get()
    if (oldValue != expectedValue) return false
    set(newValue)
    return true
}

@PublishedApi
internal fun <T> KMutableProperty0<T>.compareAndExchangeField(expectedValue: T, newValue: T): T {
    val oldValue = get()
    if (oldValue == expectedValue) set(newValue)
    return oldValue
}

@PublishedApi
internal fun <T> KMutableProperty0<T>.getAndSetField(newValue: T): T {
    val oldValue = get()
    set(newValue)
    return oldValue
}

@PublishedApi
internal fun KMutableProperty0<Short>.getAndAddField(delta: Short): Short {
    val oldValue = get()
    set((oldValue.toInt() + delta.toInt()).toShort())
    return oldValue
}

@PublishedApi
internal fun KMutableProperty0<Int>.getAndAddField(delta: Int): Int {
    val oldValue = get()
    set(oldValue + delta)
    return oldValue
}

@PublishedApi
internal fun KMutableProperty0<Long>.getAndAddField(delta: Long): Long {
    val oldValue = get()
    set(oldValue + delta)
    return oldValue
}

@PublishedApi
internal fun KMutableProperty0<Byte>.getAndAddField(delta: Byte): Byte {
    val oldValue = get()
    set((oldValue.toInt() + delta.toInt()).toByte())
    return oldValue
}
