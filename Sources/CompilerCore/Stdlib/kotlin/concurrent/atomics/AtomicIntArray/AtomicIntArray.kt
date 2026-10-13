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
     * Returns the number of elements in the array.
     */
    public val size: Int
        get() = __kkSize(this)

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
