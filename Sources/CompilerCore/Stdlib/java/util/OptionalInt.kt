package java.util

import java.util.function.IntConsumer
import java.util.function.IntSupplier
import java.util.stream.IntStream

public class OptionalInt private constructor(private val present: Boolean, private val value: Int) {
    public fun getAsInt(): Int {
        if (!present) throw NoSuchElementException("No value present")
        return value
    }

    public fun isPresent(): Boolean = present
    public fun isEmpty(): Boolean = !present
    public fun orElse(other: Int): Int = if (present) value else other
    public fun orElseGet(supplier: IntSupplier): Int = if (present) value else supplier.getAsInt()
    public fun orElseThrow(): Int = getAsInt()

    public fun ifPresent(action: IntConsumer) {
        if (present) action.accept(value)
    }

    public fun stream(): IntStream = if (present) IntStream.of(value) else IntStream.empty()

    override fun equals(other: Any?): Boolean =
        this === other || other is OptionalInt && present == other.present && (!present || value == other.value)

    override fun hashCode(): Int = if (present) value.hashCode() else 0
    override fun toString(): String = if (present) "OptionalInt[$value]" else "OptionalInt.empty"

    public companion object {
        public fun empty(): OptionalInt = OptionalInt(false, 0)
        public fun of(value: Int): OptionalInt = OptionalInt(true, value)
    }
}
