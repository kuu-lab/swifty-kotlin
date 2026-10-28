package java.util.stream

import java.util.OptionalDouble
import java.util.function.DoubleBinaryOperator
import java.util.function.DoubleConsumer
import java.util.function.DoublePredicate
import java.util.function.DoubleUnaryOperator

public class DoubleStream private constructor(private val values: Sequence<Double>) {
    public fun filter(predicate: DoublePredicate): DoubleStream =
        DoubleStream(values.filter { predicate.test(it) })

    public fun map(mapper: DoubleUnaryOperator): DoubleStream =
        DoubleStream(values.map { mapper.applyAsDouble(it) })

    public fun limit(maxSize: Long): DoubleStream {
        if (maxSize < 0) throw IllegalArgumentException("Max size must be non-negative")
        return DoubleStream(values.streamLimit(maxSize))
    }

    public fun skip(count: Long): DoubleStream {
        if (count < 0) throw IllegalArgumentException("Skip count must be non-negative")
        return DoubleStream(values.streamSkip(count))
    }

    public fun forEach(action: DoubleConsumer) {
        for (value in values) action.accept(value)
    }

    public fun count(): Long = values.streamCount()
    public fun sum(): Double { var result = 0.0; for (value in values) result += value; return result }

    public fun average(): OptionalDouble {
        var result = 0.0
        var count = 0L
        for (value in values) {
            result += value
            count++
        }
        return if (count == 0L) OptionalDouble.empty()
        else OptionalDouble.of(result / count.toDouble())
    }

    public fun min(): OptionalDouble {
        val result = values.minOrNull() ?: return OptionalDouble.empty()
        return OptionalDouble.of(result)
    }

    public fun max(): OptionalDouble {
        val result = values.maxOrNull() ?: return OptionalDouble.empty()
        return OptionalDouble.of(result)
    }

    public fun findFirst(): OptionalDouble {
        val iterator = values.iterator()
        return if (iterator.hasNext()) OptionalDouble.of(iterator.next()) else OptionalDouble.empty()
    }

    public fun findAny(): OptionalDouble = findFirst()
    public fun toArray(): DoubleArray = values.toList().toDoubleArray()
    public fun boxed(): Stream<Double> = Stream.fromSequence(values)

    public fun reduce(identity: Double, operator: DoubleBinaryOperator): Double {
        var result = identity
        for (value in values) result = operator.applyAsDouble(result, value)
        return result
    }

    public fun anyMatch(predicate: DoublePredicate): Boolean {
        for (value in values) if (predicate.test(value)) return true
        return false
    }

    public fun allMatch(predicate: DoublePredicate): Boolean {
        for (value in values) if (!predicate.test(value)) return false
        return true
    }

    public fun noneMatch(predicate: DoublePredicate): Boolean {
        for (value in values) if (predicate.test(value)) return false
        return true
    }

    public companion object {
        internal fun fromSequence(values: Sequence<Double>): DoubleStream = DoubleStream(values)

        public fun of(vararg values: Double): DoubleStream =
            DoubleStream(streamSequence { values.iterator() })

        public fun empty(): DoubleStream = DoubleStream(streamSequence { doubleArrayOf().iterator() })
    }
}
