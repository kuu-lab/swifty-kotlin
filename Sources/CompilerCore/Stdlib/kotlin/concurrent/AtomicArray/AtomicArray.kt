@file:OptIn(kotlin.ExperimentalStdlibApi::class)

package kotlin.concurrent

import kotlin.internal.KsSymbolName

/**
 * Kotlin source-backed members for the legacy `kotlin.concurrent.AtomicArray`.
 * The runtime owns the atomic storage; these methods provide bounds checks and
 * reuse the reference-array ABI shared with `kotlin.concurrent.atomics`.
 */
@SinceKotlin("1.9")
@ExperimentalStdlibApi
public class AtomicArray<T> private constructor() {
    public val length: Int
        get() = atomicArraySizeBridge(this)

    public operator fun get(index: Int): T {
        checkIndex(index)
        return atomicArrayLoadBridge(this, index)
    }

    public operator fun set(index: Int, newValue: T): Unit {
        checkIndex(index)
        atomicArrayStoreBridge(this, index, newValue)
    }

    public fun getAndSet(index: Int, newValue: T): T {
        checkIndex(index)
        return atomicArrayExchangeBridge(this, index, newValue)
    }

    public fun compareAndSet(index: Int, expectedValue: T, newValue: T): Boolean {
        checkIndex(index)
        return atomicArrayCompareAndSetBridge(this, index, expectedValue, newValue)
    }

    public fun compareAndExchange(index: Int, expectedValue: T, newValue: T): T {
        checkIndex(index)
        return atomicArrayCompareAndExchangeBridge(this, index, expectedValue, newValue)
    }

    public override fun toString(): String {
        val builder = StringBuilder()
        builder.append("[")
        var index = 0
        while (index < length) {
            if (index > 0) builder.append(", ")
            builder.append(this[index])
            index++
        }
        builder.append("]")
        return builder.toString()
    }

    private fun checkIndex(index: Int) {
        val size = length
        if (index < 0 || index >= size) {
            throw IndexOutOfBoundsException("The index $index is out of the bounds of the AtomicArray with size $size.")
        }
    }
}

@KsSymbolName("kk_atomic_ref_array_size")
private external fun <T> atomicArraySizeBridge(receiver: AtomicArray<T>): Int

@KsSymbolName("kk_atomic_ref_array_loadAt")
private external fun <T> atomicArrayLoadBridge(receiver: AtomicArray<T>, index: Int): T

@KsSymbolName("kk_atomic_ref_array_storeAt")
private external fun <T> atomicArrayStoreBridge(receiver: AtomicArray<T>, index: Int, value: T): Unit

@KsSymbolName("kk_atomic_ref_array_exchangeAt")
private external fun <T> atomicArrayExchangeBridge(receiver: AtomicArray<T>, index: Int, value: T): T

@KsSymbolName("kk_atomic_ref_array_compareAndSetAt")
private external fun <T> atomicArrayCompareAndSetBridge(
    receiver: AtomicArray<T>,
    index: Int,
    expectedValue: T,
    newValue: T
): Boolean

@KsSymbolName("kk_atomic_ref_array_compareAndExchangeAt")
private external fun <T> atomicArrayCompareAndExchangeBridge(
    receiver: AtomicArray<T>,
    index: Int,
    expectedValue: T,
    newValue: T
): T
