package java.util.stream

import java.util.OptionalDouble
import java.util.function.DoubleBinaryOperator
import java.util.function.DoubleConsumer
import java.util.function.DoublePredicate
import java.util.function.DoubleUnaryOperator

public class DoubleStream private constructor(private val values: Sequence<Double>) {
    private var consumed: Boolean = false

    private fun consumeValues(): Sequence<Double> {
        if (consumed) throw IllegalStateException("stream has already been operated upon or closed")
        consumed = true
        return values
    }

    public fun filter(predicate: DoublePredicate): DoubleStream =
        DoubleStream(consumeValues().filter { predicate.test(it) })

    public fun map(mapper: DoubleUnaryOperator): DoubleStream =
        DoubleStream(consumeValues().map { mapper.applyAsDouble(it) })

    public fun limit(maxSize: Long): DoubleStream {
        if (maxSize < 0) throw IllegalArgumentException("Max size must be non-negative")
        return DoubleStream(consumeValues().streamLimit(maxSize))
    }

    public fun skip(count: Long): DoubleStream {
        if (count < 0) throw IllegalArgumentException("Skip count must be non-negative")
        return DoubleStream(consumeValues().streamSkip(count))
    }

    public fun forEach(action: DoubleConsumer) {
        for (value in consumeValues()) action.accept(value)
    }

    public fun count(): Long = consumeValues().streamCount()
    public fun sum(): Double { var result = 0.0; for (value in consumeValues()) result += value; return result }

    public fun average(): OptionalDouble {
        var result = 0.0
        var count = 0L
        for (value in consumeValues()) {
            result += value
            count++
        }
        return if (count == 0L) OptionalDouble.empty()
        else OptionalDouble.of(result / count.toDouble())
    }

    public fun min(): OptionalDouble {
        val result = consumeValues().minOrNull() ?: return OptionalDouble.empty()
        return OptionalDouble.of(result)
    }

    public fun max(): OptionalDouble {
        val result = consumeValues().maxOrNull() ?: return OptionalDouble.empty()
        return OptionalDouble.of(result)
    }

    public fun findFirst(): OptionalDouble {
        val iterator = consumeValues().iterator()
        return if (iterator.hasNext()) OptionalDouble.of(iterator.next()) else OptionalDouble.empty()
    }

    public fun findAny(): OptionalDouble = findFirst()
    public fun toArray(): DoubleArray = consumeValues().toList().toDoubleArray()
    public fun boxed(): Stream<Double> = Stream.fromSequence(consumeValues())

    public fun reduce(identity: Double, operator: DoubleBinaryOperator): Double {
        var result = identity
        for (value in consumeValues()) result = operator.applyAsDouble(result, value)
        return result
    }

    public fun anyMatch(predicate: DoublePredicate): Boolean {
        for (value in consumeValues()) if (predicate.test(value)) return true
        return false
    }

    public fun allMatch(predicate: DoublePredicate): Boolean {
        for (value in consumeValues()) if (!predicate.test(value)) return false
        return true
    }

    public fun noneMatch(predicate: DoublePredicate): Boolean {
        for (value in consumeValues()) if (predicate.test(value)) return false
        return true
    }

    public companion object {
        internal fun fromSequence(values: Sequence<Double>): DoubleStream = DoubleStream(values)

        public fun of(vararg values: Double): DoubleStream =
            DoubleStream(streamSequence { values.iterator() })

        public fun empty(): DoubleStream = DoubleStream(streamSequence { doubleArrayOf().iterator() })

        public fun iterate(seed: Double, next: DoubleUnaryOperator): DoubleStream =
            DoubleStream(streamSequence {
                object : Iterator<Double> {
                    var current = seed

                    override fun hasNext(): Boolean = true

                    override fun next(): Double {
                        val value = current
                        current = next.applyAsDouble(value)
                        return value
                    }
                }
            })

        public fun iterate(seed: Double, hasNext: DoublePredicate, next: DoubleUnaryOperator): DoubleStream =
            DoubleStream(streamSequence {
                object : Iterator<Double> {
                    var current = seed
                    var first = true
                    var advanced = false
                    var valid = false

                    private fun advance() {
                        if (advanced) return
                        if (first) first = false
                        else current = next.applyAsDouble(current)
                        valid = hasNext.test(current)
                        advanced = true
                    }

                    override fun hasNext(): Boolean {
                        advance()
                        return valid
                    }

                    override fun next(): Double {
                        advance()
                        if (!valid) throw NoSuchElementException()
                        advanced = false
                        return current
                    }
                }
            })
    }
}
