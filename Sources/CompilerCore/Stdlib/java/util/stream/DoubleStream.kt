package java.util.stream

import java.util.OptionalDouble
import java.util.function.DoubleBinaryOperator
import java.util.function.DoubleConsumer
import java.util.function.DoublePredicate
import java.util.function.DoubleUnaryOperator

public class DoubleStream private constructor(private val values: DoubleArray) {
    public fun filter(predicate: DoublePredicate): DoubleStream {
        val result = mutableListOf<Double>()
        for (value in values) if (predicate.test(value)) result.add(value)
        return of(*result.toDoubleArray())
    }

    public fun map(mapper: DoubleUnaryOperator): DoubleStream {
        val result = DoubleArray(values.size)
        var index = 0
        while (index < values.size) { result[index] = mapper.applyAsDouble(values[index]); index++ }
        return of(*result)
    }

    public fun forEach(action: DoubleConsumer) { for (value in values) action.accept(value) }
    public fun count(): Long = values.size.toLong()
    public fun sum(): Double { var result = 0.0; for (value in values) result += value; return result }
    public fun average(): OptionalDouble = if (values.isEmpty()) OptionalDouble.empty()
    else OptionalDouble.of(sum() / values.size.toDouble())
    public fun min(): OptionalDouble = if (values.isEmpty()) OptionalDouble.empty() else OptionalDouble.of(values.minOrNull()!!)
    public fun max(): OptionalDouble = if (values.isEmpty()) OptionalDouble.empty() else OptionalDouble.of(values.maxOrNull()!!)
    public fun findFirst(): OptionalDouble = if (values.isEmpty()) OptionalDouble.empty() else OptionalDouble.of(values[0])
    public fun findAny(): OptionalDouble = findFirst()
    public fun toArray(): DoubleArray = values.copyOf()
    public fun boxed(): Stream<Double> = Stream.of(*values.toTypedArray())

    public fun reduce(identity: Double, operator: DoubleBinaryOperator): Double {
        var result = identity
        for (value in values) result = operator.applyAsDouble(result, value)
        return result
    }

    public fun anyMatch(predicate: DoublePredicate): Boolean { for (value in values) if (predicate.test(value)) return true; return false }
    public fun allMatch(predicate: DoublePredicate): Boolean { for (value in values) if (!predicate.test(value)) return false; return true }
    public fun noneMatch(predicate: DoublePredicate): Boolean = !anyMatch(predicate)

    public companion object {
        public fun of(vararg values: Double): DoubleStream = DoubleStream(values.copyOf())
        public fun empty(): DoubleStream = DoubleStream(DoubleArray(0))
    }
}
