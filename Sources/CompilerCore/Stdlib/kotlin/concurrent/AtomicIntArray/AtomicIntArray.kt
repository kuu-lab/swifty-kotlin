@file:OptIn(kotlin.ExperimentalStdlibApi::class)

package kotlin.concurrent

/**
 * Kotlin source-backed members for the legacy `kotlin.concurrent.AtomicIntArray`.
 *
 * The array's synchronized storage remains in the runtime. These members reuse
 * the `*At` boundary functions from `AtomicArrayCompatMigration.kt`, keeping
 * bounds checks and the raw atomic operations in one implementation.
 */
@SinceKotlin("1.9")
@ExperimentalStdlibApi
public class AtomicIntArray private constructor() {
    public fun compareAndExchange(index: Int, expectedValue: Int, newValue: Int): Int =
        compareAndExchangeAt(index, expectedValue, newValue)

    public fun compareAndSet(index: Int, expectedValue: Int, newValue: Int): Boolean =
        compareAndExchangeAt(index, expectedValue, newValue) == expectedValue

    public val length: Int
        get() = size

    public override fun toString(): String {
        val builder = StringBuilder()
        builder.append("[")
        var index = 0
        while (index < size) {
            if (index > 0) builder.append(", ")
            builder.append(loadAt(index))
            index++
        }
        builder.append("]")
        return builder.toString()
    }
}
