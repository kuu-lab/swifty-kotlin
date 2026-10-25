package java.util

import java.util.function.LongConsumer
import java.util.function.LongSupplier
import java.util.stream.LongStream

public class OptionalLong private constructor(private val present: Boolean, private val value: Long) {
    public fun getAsLong(): Long {
        if (!present) throw NoSuchElementException("No value present")
        return value
    }

    public fun isPresent(): Boolean = present
    public fun isEmpty(): Boolean = !present
    public fun orElse(other: Long): Long = if (present) value else other
    public fun orElseGet(supplier: LongSupplier): Long = if (present) value else supplier.getAsLong()
    public fun orElseThrow(): Long = getAsLong()

    public fun ifPresent(action: LongConsumer) {
        if (present) action.accept(value)
    }

    public fun stream(): LongStream = if (present) LongStream.of(value) else LongStream.empty()

    override fun equals(other: Any?): Boolean =
        this === other || other is OptionalLong && present == other.present && (!present || value == other.value)

    override fun hashCode(): Int = if (present) value.hashCode() else 0
    override fun toString(): String = if (present) "OptionalLong[$value]" else "OptionalLong.empty"

    public companion object {
        public fun empty(): OptionalLong = OptionalLong(false, 0L)
        public fun of(value: Long): OptionalLong = OptionalLong(true, value)
    }
}
