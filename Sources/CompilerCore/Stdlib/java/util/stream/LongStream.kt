package java.util.stream

import java.util.OptionalDouble
import java.util.OptionalLong
import java.util.function.LongBinaryOperator
import java.util.function.LongConsumer
import java.util.function.LongPredicate
import java.util.function.LongUnaryOperator

public class LongStream private constructor(private val values: Sequence<Long>) {
    public fun filter(predicate: LongPredicate): LongStream =
        LongStream(values.filter { predicate.test(it) })

    public fun map(mapper: LongUnaryOperator): LongStream =
        LongStream(values.map { mapper.applyAsLong(it) })

    public fun limit(maxSize: Long): LongStream {
        if (maxSize < 0) throw IllegalArgumentException("Max size must be non-negative")
        return LongStream(values.streamLimit(maxSize))
    }

    public fun skip(count: Long): LongStream {
        if (count < 0) throw IllegalArgumentException("Skip count must be non-negative")
        return LongStream(values.streamSkip(count))
    }

    public fun forEach(action: LongConsumer) {
        for (value in values) action.accept(value)
    }

    public fun count(): Long = values.streamCount()
    public fun sum(): Long { var result = 0L; for (value in values) result += value; return result }

    public fun average(): OptionalDouble {
        var result = 0.0
        var count = 0L
        for (value in values) {
            result += value.toDouble()
            count++
        }
        return if (count == 0L) OptionalDouble.empty()
        else OptionalDouble.of(result / count.toDouble())
    }

    public fun min(): OptionalLong {
        val iterator = values.iterator()
        if (!iterator.hasNext()) return OptionalLong.empty()
        var result = iterator.next()
        while (iterator.hasNext()) {
            val value = iterator.next()
            if (value < result) result = value
        }
        return OptionalLong.of(result)
    }

    public fun max(): OptionalLong {
        val iterator = values.iterator()
        if (!iterator.hasNext()) return OptionalLong.empty()
        var result = iterator.next()
        while (iterator.hasNext()) {
            val value = iterator.next()
            if (value > result) result = value
        }
        return OptionalLong.of(result)
    }

    public fun findFirst(): OptionalLong {
        val iterator = values.iterator()
        return if (iterator.hasNext()) OptionalLong.of(iterator.next()) else OptionalLong.empty()
    }

    public fun findAny(): OptionalLong = findFirst()
    public fun toArray(): LongArray = values.toList().toLongArray()
    public fun boxed(): Stream<Long> = Stream.fromSequence(values)

    public fun reduce(identity: Long, operator: LongBinaryOperator): Long {
        var result = identity
        for (value in values) result = operator.applyAsLong(result, value)
        return result
    }

    public fun anyMatch(predicate: LongPredicate): Boolean {
        for (value in values) if (predicate.test(value)) return true
        return false
    }

    public fun allMatch(predicate: LongPredicate): Boolean {
        for (value in values) if (!predicate.test(value)) return false
        return true
    }

    public fun noneMatch(predicate: LongPredicate): Boolean {
        for (value in values) if (predicate.test(value)) return false
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
