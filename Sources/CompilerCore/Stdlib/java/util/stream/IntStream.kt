package java.util.stream

import java.util.OptionalDouble
import java.util.OptionalInt
import java.util.function.IntBinaryOperator
import java.util.function.IntConsumer
import java.util.function.IntFunction
import java.util.function.IntPredicate
import java.util.function.IntUnaryOperator

public class IntStream private constructor(private val values: Sequence<Int>) {
    private var consumed: Boolean = false

    private fun consumeValues(): Sequence<Int> {
        if (consumed) throw IllegalStateException("stream has already been operated upon or closed")
        consumed = true
        return values
    }

    public fun filter(predicate: IntPredicate): IntStream =
        IntStream(consumeValues().filter { predicate.test(it) })

    public fun map(mapper: IntUnaryOperator): IntStream =
        IntStream(consumeValues().map { mapper.applyAsInt(it) })

    public fun <R> mapToObj(mapper: IntFunction<out R>): Stream<R> =
        Stream.fromSequence(consumeValues().map { mapper.apply(it) })

    public fun limit(maxSize: Long): IntStream {
        if (maxSize < 0) throw IllegalArgumentException("Max size must be non-negative")
        return IntStream(consumeValues().streamLimit(maxSize))
    }

    public fun skip(count: Long): IntStream {
        if (count < 0) throw IllegalArgumentException("Skip count must be non-negative")
        return IntStream(consumeValues().streamSkip(count))
    }

    public fun forEach(action: IntConsumer) {
        for (value in consumeValues()) action.accept(value)
    }

    public fun count(): Long = consumeValues().streamCount()

    public fun sum(): Int {
        var result = 0
        for (value in consumeValues()) result += value
        return result
    }

    public fun average(): OptionalDouble {
        var total = 0L
        var count = 0L
        for (value in consumeValues()) {
            total += value.toLong()
            count++
        }
        return if (count == 0L) OptionalDouble.empty()
        else OptionalDouble.of(total.toDouble() / count.toDouble())
    }

    public fun min(): OptionalInt {
        val iterator = consumeValues().iterator()
        if (!iterator.hasNext()) return OptionalInt.empty()
        var result = iterator.next()
        while (iterator.hasNext()) {
            val value = iterator.next()
            if (value < result) result = value
        }
        return OptionalInt.of(result)
    }

    public fun max(): OptionalInt {
        val iterator = consumeValues().iterator()
        if (!iterator.hasNext()) return OptionalInt.empty()
        var result = iterator.next()
        while (iterator.hasNext()) {
            val value = iterator.next()
            if (value > result) result = value
        }
        return OptionalInt.of(result)
    }

    public fun findFirst(): OptionalInt {
        val iterator = consumeValues().iterator()
        return if (iterator.hasNext()) OptionalInt.of(iterator.next()) else OptionalInt.empty()
    }

    public fun findAny(): OptionalInt = findFirst()
    public fun toArray(): IntArray = consumeValues().toList().toIntArray()
    public fun boxed(): Stream<Int> = Stream.fromSequence(consumeValues())

    public fun reduce(identity: Int, operator: IntBinaryOperator): Int {
        var result = identity
        for (value in consumeValues()) result = operator.applyAsInt(result, value)
        return result
    }

    public fun anyMatch(predicate: IntPredicate): Boolean {
        for (value in consumeValues()) if (predicate.test(value)) return true
        return false
    }

    public fun allMatch(predicate: IntPredicate): Boolean {
        for (value in consumeValues()) if (!predicate.test(value)) return false
        return true
    }

    public fun noneMatch(predicate: IntPredicate): Boolean {
        for (value in consumeValues()) if (predicate.test(value)) return false
        return true
    }

    public companion object {
        internal fun fromSequence(values: Sequence<Int>): IntStream = IntStream(values)

        public fun of(vararg values: Int): IntStream =
            IntStream(streamSequence { values.iterator() })

        public fun empty(): IntStream = IntStream(streamSequence { intArrayOf().iterator() })

        public fun range(startInclusive: Int, endExclusive: Int): IntStream {
            if (startInclusive >= endExclusive) return empty()
            val range = startInclusive until endExclusive
            return IntStream(streamSequence { range.iterator() })
        }

        public fun rangeClosed(startInclusive: Int, endInclusive: Int): IntStream {
            if (startInclusive > endInclusive) return empty()
            val range = startInclusive..endInclusive
            return IntStream(streamSequence { range.iterator() })
        }
    }
}
