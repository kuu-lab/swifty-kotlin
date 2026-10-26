package java.util.stream

import java.util.OptionalDouble
import java.util.OptionalLong
import java.util.function.LongBinaryOperator
import java.util.function.LongConsumer
import java.util.function.LongPredicate
import java.util.function.LongUnaryOperator

public class LongStream private constructor(private val values: LongArray) {
    public fun filter(predicate: LongPredicate): LongStream {
        val result = mutableListOf<Long>()
        for (value in values) if (predicate.test(value)) result.add(value)
        return of(*result.toLongArray())
    }

    public fun map(mapper: LongUnaryOperator): LongStream {
        val result = LongArray(values.size)
        var index = 0
        while (index < values.size) { result[index] = mapper.applyAsLong(values[index]); index++ }
        return of(*result)
    }

    public fun forEach(action: LongConsumer) { for (value in values) action.accept(value) }
    public fun count(): Long = values.size.toLong()
    public fun sum(): Long { var result = 0L; for (value in values) result += value; return result }
    public fun average(): OptionalDouble = if (values.isEmpty()) OptionalDouble.empty()
    else OptionalDouble.of(sum().toDouble() / values.size.toDouble())
    public fun min(): OptionalLong = if (values.isEmpty()) OptionalLong.empty() else OptionalLong.of(values.minOrNull()!!)
    public fun max(): OptionalLong = if (values.isEmpty()) OptionalLong.empty() else OptionalLong.of(values.maxOrNull()!!)
    public fun findFirst(): OptionalLong = if (values.isEmpty()) OptionalLong.empty() else OptionalLong.of(values[0])
    public fun findAny(): OptionalLong = findFirst()
    public fun toArray(): LongArray = values.copyOf()
    public fun boxed(): Stream<Long> = Stream.of(*values.toTypedArray())

    public fun reduce(identity: Long, operator: LongBinaryOperator): Long {
        var result = identity
        for (value in values) result = operator.applyAsLong(result, value)
        return result
    }

    public fun anyMatch(predicate: LongPredicate): Boolean { for (value in values) if (predicate.test(value)) return true; return false }
    public fun allMatch(predicate: LongPredicate): Boolean { for (value in values) if (!predicate.test(value)) return false; return true }
    public fun noneMatch(predicate: LongPredicate): Boolean = !anyMatch(predicate)

    public companion object {
        public fun of(vararg values: Long): LongStream = LongStream(values.copyOf())
        public fun empty(): LongStream = LongStream(LongArray(0))

        public fun range(startInclusive: Long, endExclusive: Long): LongStream {
            if (startInclusive >= endExclusive) return empty()
            val result = mutableListOf<Long>()
            var value = startInclusive
            while (value < endExclusive) { result.add(value); value++ }
            return of(*result.toLongArray())
        }

        public fun rangeClosed(startInclusive: Long, endInclusive: Long): LongStream {
            if (startInclusive > endInclusive) return empty()
            val result = mutableListOf<Long>()
            var value = startInclusive
            while (true) { result.add(value); if (value == endInclusive) break; value++ }
            return of(*result.toLongArray())
        }
    }
}
