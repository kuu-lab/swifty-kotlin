@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package kotlin.concurrent.atomics

import kotlin.internal.KsSymbolName

/**
 * An array of references in which elements may be updated atomically.
 *
 * The atomic storage stays in the runtime `kk_atomic_ref_array_*` box and CAS
 * uses identity semantics. These members add the bounds checks the stdlib
 * contract requires and keep the element type marshal correct for every `T`,
 * including nullable value types such as `Int?`.
 */
@SinceKotlin("2.1")
@ExperimentalAtomicApi
public class AtomicArray<T> {
    @KsSymbolName("kk_atomic_ref_array_new")
    public constructor(size: Int)

    /**
     * Atomically stores the [newValue] into the element of this [AtomicArray]
     * at the given [index] and returns the old value of the element.
     */
    public fun compareAndExchange(index: Int, expectedValue: T, newValue: T): T =
        compareAndExchangeAt(index, expectedValue, newValue)

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
    public fun compareAndSet(index: Int, expectedValue: T, newValue: T): Boolean =
        compareAndSetAt(index, expectedValue, newValue)

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
     * Atomically stores the [newValue] into the element of this [AtomicArray]
     * at the given [index] and returns the old value of the element.
     */
    public fun getAndSet(index: Int, newValue: T): T =
        exchangeAt(index, newValue)

    /**
     * Returns the element of this [AtomicArray] at the given [index].
     */
    public operator fun get(index: Int): T =
        loadAt(index)

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
    public operator fun set(index: Int, value: T): Unit =
        storeAt(index, value)

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
     * Returns the number of elements in the array.
     */
    public val length: Int
        get() = size

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
