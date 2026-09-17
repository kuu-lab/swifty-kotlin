@file:OptIn(kotlin.ExperimentalStdlibApi::class)

package kotlin.concurrent

/**
 * Kotlin source-backed members for the legacy `kotlin.concurrent.AtomicLongArray`.
 *
 * The array's synchronized storage remains in the runtime. These members reuse
 * the `*At` boundary functions from `AtomicArrayCompatMigration.kt`, keeping
 * bounds checks and the raw atomic operations in one implementation.
 */
@SinceKotlin("1.9")
@ExperimentalStdlibApi
public class AtomicLongArray private constructor() {
    public fun compareAndExchange(index: Int, expectedValue: Long, newValue: Long): Long =
        compareAndExchangeAt(index, expectedValue, newValue)

    public fun compareAndSet(index: Int, expectedValue: Long, newValue: Long): Boolean =
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
