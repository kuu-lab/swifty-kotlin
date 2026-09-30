@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package kotlin.concurrent.atomics

import kotlin.internal.KsSymbolName

@KsSymbolName("kk_atomic_int_array_size")
private external fun __kkSize(array: AtomicIntArray): Int

/**
 * An array of ints in which elements may be updated atomically.
 */
@SinceKotlin("2.1")
@ExperimentalAtomicApi
public class AtomicIntArray private constructor() {
    /**
     * Atomically stores the [newValue] into the element of this [AtomicIntArray]
     * at the given [index] if the current value equals the [expectedValue]
     * and returns the old value of the element.
     */
    public fun compareAndExchange(index: Int, expectedValue: Int, newValue: Int): Int =
        compareAndExchangeAt(index, expectedValue, newValue)

    /**
     * Atomically stores the [newValue] into the element of this [AtomicIntArray]
     * at the given [index] if the current value equals the [expectedValue]
     * and returns true if the operation was successful.
     */
    public fun compareAndSet(index: Int, expectedValue: Int, newValue: Int): Boolean =
        compareAndExchangeAt(index, expectedValue, newValue) == expectedValue

    /**
     * Returns the number of elements in the array.
     */
    public val size: Int
        get() = __kkSize(this)

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
}
