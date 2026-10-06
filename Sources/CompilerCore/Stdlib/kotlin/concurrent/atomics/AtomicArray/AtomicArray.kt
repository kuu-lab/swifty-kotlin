@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package kotlin.concurrent.atomics

import kotlin.internal.KsSymbolName

/**
 * An array of references in which elements may be updated atomically.
 *
 * The atomic storage stays in the runtime `kk_atomic_ref_array_*` box and CAS
 * uses identity semantics. These members add the bounds checks the stdlib
 * contract requires and bridge through `private external` members so `T` stays
 * on the class-type-parameter marshal path rather than the function-generic
 * extern boundary (which mis-decodes nullable value types such as `Int?`).
 */
@SinceKotlin("2.1")
@ExperimentalAtomicApi
public class AtomicArray<T> private constructor() {
    /**
     * Atomically stores the [newValue] into the element of this [AtomicArray]
     * at the given [index] if the current value equals the [expectedValue]
     * and returns the old value of the element.
     */
    public fun compareAndExchangeAt(index: Int, expectedValue: T, newValue: T): T {
        checkIndex(index)
        return __kkAtomicRefArrayCompareAndExchangeAt(index, expectedValue, newValue)
    }

    /**
     * Atomically stores the [newValue] into the element of this [AtomicArray]
     * at the given [index] if the current value equals the [expectedValue]
     * and returns true if the operation was successful.
     */
    public fun compareAndSetAt(index: Int, expectedValue: T, newValue: T): Boolean {
        checkIndex(index)
        return __kkAtomicRefArrayCompareAndSetAt(index, expectedValue, newValue)
    }

    /**
     * Atomically stores the [newValue] into the element of this [AtomicArray]
     * at the given [index] and returns the old value of the element.
     */
    public fun exchangeAt(index: Int, newValue: T): T {
        checkIndex(index)
        return __kkAtomicRefArrayExchangeAt(index, newValue)
    }

    /**
     * Returns the element of this [AtomicArray] at the given [index].
     */
    public fun loadAt(index: Int): T {
        checkIndex(index)
        return __kkAtomicRefArrayLoadAt(index)
    }

    /**
     * Atomically stores the [value] into the element of this [AtomicArray]
     * at the given [index].
     */
    public fun storeAt(index: Int, value: T): Unit {
        checkIndex(index)
        __kkAtomicRefArrayStoreAt(index, value)
    }

    /**
     * Returns the number of elements in the array.
     */
    public val size: Int
        get() = __kkAtomicRefArraySize()

    /**
     * Returns a string representation of this array.
     */
    public override fun toString(): String {
        val builder = StringBuilder()
        builder.append("[")
        var index = 0
        while (index < size) {
            if (index > 0) {
                builder.append(", ")
            }
            builder.append(loadAt(index))
            index++
        }
        builder.append("]")
        return builder.toString()
    }

    private fun checkIndex(index: Int) {
        val count = size
        if (index < 0 || index >= count) {
            throw IndexOutOfBoundsException("The index $index is out of the bounds of the AtomicArray with size $count.")
        }
    }

    @KsSymbolName("kk_atomic_ref_array_size")
    private external fun __kkAtomicRefArraySize(): Int

    @KsSymbolName("kk_atomic_ref_array_loadAt")
    private external fun __kkAtomicRefArrayLoadAt(index: Int): T

    @KsSymbolName("kk_atomic_ref_array_storeAt")
    private external fun __kkAtomicRefArrayStoreAt(index: Int, value: T): Unit

    @KsSymbolName("kk_atomic_ref_array_exchangeAt")
    private external fun __kkAtomicRefArrayExchangeAt(index: Int, newValue: T): T

    @KsSymbolName("kk_atomic_ref_array_compareAndSetAt")
    private external fun __kkAtomicRefArrayCompareAndSetAt(index: Int, expectedValue: T, newValue: T): Boolean

    @KsSymbolName("kk_atomic_ref_array_compareAndExchangeAt")
    private external fun __kkAtomicRefArrayCompareAndExchangeAt(index: Int, expectedValue: T, newValue: T): T
}
