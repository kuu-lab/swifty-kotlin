package java.util.stream

import java.util.OptionalDouble
import java.util.OptionalLong
import java.util.function.LongBinaryOperator
import java.util.function.LongConsumer
import java.util.function.LongPredicate
import java.util.function.LongUnaryOperator

public class LongStream private constructor(private val values: Sequence<Long>) {
    private var consumed: Boolean = false

    private fun consumeValues(): Sequence<Long> {
        if (consumed) throw IllegalStateException("stream has already been operated upon or closed")
        consumed = true
        return values
    }

    public fun filter(predicate: LongPredicate): LongStream =
        LongStream(consumeValues().filter { predicate.test(it) })

    public fun map(mapper: LongUnaryOperator): LongStream =
        LongStream(consumeValues().map { mapper.applyAsLong(it) })

    public fun limit(maxSize: Long): LongStream {
        if (maxSize < 0) throw IllegalArgumentException("Max size must be non-negative")
        return LongStream(consumeValues().streamLimit(maxSize))
    }

    public fun skip(count: Long): LongStream {
        if (count < 0) throw IllegalArgumentException("Skip count must be non-negative")
        return LongStream(consumeValues().streamSkip(count))
    }

    public fun forEach(action: LongConsumer) {
        for (value in consumeValues()) action.accept(value)
    }

    public fun count(): Long = consumeValues().streamCount()
    public fun sum(): Long { var result = 0L; for (value in consumeValues()) result += value; return result }

    public fun average(): OptionalDouble {
        var result = 0.0
        var count = 0L
        for (value in consumeValues()) {
            result += value.toDouble()
            count++
        }
        return if (count == 0L) OptionalDouble.empty()
        else OptionalDouble.of(result / count.toDouble())
    }

    public fun min(): OptionalLong {
        val iterator = consumeValues().iterator()
        if (!iterator.hasNext()) return OptionalLong.empty()
        var result = iterator.next()
        while (iterator.hasNext()) {
            val value = iterator.next()
            if (value < result) result = value
        }
        return OptionalLong.of(result)
    }

    public fun max(): OptionalLong {
        val iterator = consumeValues().iterator()
        if (!iterator.hasNext()) return OptionalLong.empty()
        var result = iterator.next()
        while (iterator.hasNext()) {
            val value = iterator.next()
            if (value > result) result = value
        }
        return OptionalLong.of(result)
    }

    public fun findFirst(): OptionalLong {
        val iterator = consumeValues().iterator()
        return if (iterator.hasNext()) OptionalLong.of(iterator.next()) else OptionalLong.empty()
    }

    public fun findAny(): OptionalLong = findFirst()
    public fun toArray(): LongArray = consumeValues().toList().toLongArray()
    public fun boxed(): Stream<Long> = Stream.fromSequence(consumeValues())

    public fun reduce(identity: Long, operator: LongBinaryOperator): Long {
        var result = identity
        for (value in consumeValues()) result = operator.applyAsLong(result, value)
        return result
    }

    public fun anyMatch(predicate: LongPredicate): Boolean {
        for (value in consumeValues()) if (predicate.test(value)) return true
        return false
    }

    public fun allMatch(predicate: LongPredicate): Boolean {
        for (value in consumeValues()) if (!predicate.test(value)) return false
        return true
    }

    public fun noneMatch(predicate: LongPredicate): Boolean {
        for (value in consumeValues()) if (predicate.test(value)) return false
        return true
    }

    public companion object {
        internal fun fromSequence(values: Sequence<Long>): LongStream = LongStream(values)

        public fun of(vararg values: Long): LongStream =
            LongStream(streamSequence { values.iterator() })

        public fun empty(): LongStream = LongStream(streamSequence { longArrayOf().iterator() })

        public fun range(startInclusive: Long, endExclusive: Long): LongStream {
            if (startInclusive >= endExclusive) return empty()
            val range = startInclusive until endExclusive
            return LongStream(streamSequence { range.iterator() })
        }

        public fun rangeClosed(startInclusive: Long, endInclusive: Long): LongStream {
            if (startInclusive > endInclusive) return empty()
            val range = startInclusive..endInclusive
            return LongStream(streamSequence { range.iterator() })
        }
    }
}
