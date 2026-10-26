package java.util

import java.util.function.DoubleConsumer
import java.util.function.DoubleSupplier
import java.util.stream.DoubleStream

public class OptionalDouble private constructor(private val present: Boolean, private val value: Double) {
    public fun getAsDouble(): Double {
        if (!present) throw NoSuchElementException("No value present")
        return value
    }

    public fun isPresent(): Boolean = present
    public fun isEmpty(): Boolean = !present
    public fun orElse(other: Double): Double = if (present) value else other
    public fun orElseGet(supplier: DoubleSupplier): Double = if (present) value else supplier.getAsDouble()
    public fun orElseThrow(): Double = getAsDouble()

    public fun ifPresent(action: DoubleConsumer) {
        if (present) action.accept(value)
    }

    public fun stream(): DoubleStream = if (present) DoubleStream.of(value) else DoubleStream.empty()

    override fun equals(other: Any?): Boolean =
        this === other || other is OptionalDouble && present == other.present && (!present || value.toBits() == other.value.toBits())

    override fun hashCode(): Int = if (present) value.hashCode() else 0
    override fun toString(): String = if (present) "OptionalDouble[$value]" else "OptionalDouble.empty"

    public companion object {
        public fun empty(): OptionalDouble = OptionalDouble(false, 0.0)
        public fun of(value: Double): OptionalDouble = OptionalDouble(true, value)
    }
}
