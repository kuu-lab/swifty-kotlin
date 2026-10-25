package java.util.stream

import java.util.OptionalDouble
import java.util.OptionalInt
import java.util.function.IntBinaryOperator
import java.util.function.IntConsumer
import java.util.function.IntFunction
import java.util.function.IntPredicate
import java.util.function.IntUnaryOperator

public class IntStream private constructor(private val values: IntArray) {
    public fun filter(predicate: IntPredicate): IntStream {
        val result = mutableListOf<Int>()
        for (value in values) if (predicate.test(value)) result.add(value)
        return IntStream.of(*result.toIntArray())
    }

    public fun map(mapper: IntUnaryOperator): IntStream {
        val result = IntArray(values.size)
        var index = 0
        while (index < values.size) {
            result[index] = mapper.applyAsInt(values[index])
            index++
        }
        return IntStream.of(*result)
    }

    public fun <R> mapToObj(mapper: IntFunction<out R>): Stream<R> {
        val result = mutableListOf<R>()
        for (value in values) result.add(mapper.apply(value))
        return Stream.fromIterable(result)
    }

    public fun forEach(action: IntConsumer) {
        for (value in values) action.accept(value)
    }

    public fun count(): Long = values.size.toLong()
    public fun sum(): Int {
        var result = 0
        for (value in values) result += value
        return result
    }

    public fun average(): OptionalDouble = if (values.isEmpty()) OptionalDouble.empty()
    else OptionalDouble.of(sum().toDouble() / values.size.toDouble())

    public fun min(): OptionalInt {
        if (values.isEmpty()) return OptionalInt.empty()
        var result = values[0]
        var index = 1
        while (index < values.size) { if (values[index] < result) result = values[index]; index++ }
        return OptionalInt.of(result)
    }

    public fun max(): OptionalInt {
        if (values.isEmpty()) return OptionalInt.empty()
        var result = values[0]
        var index = 1
        while (index < values.size) { if (values[index] > result) result = values[index]; index++ }
        return OptionalInt.of(result)
    }

    public fun findFirst(): OptionalInt = if (values.isEmpty()) OptionalInt.empty() else OptionalInt.of(values[0])
    public fun findAny(): OptionalInt = findFirst()
    public fun toArray(): IntArray = values.copyOf()
    public fun boxed(): Stream<Int> = Stream.of(*values.toTypedArray())
    public fun reduce(identity: Int, operator: IntBinaryOperator): Int {
        var result = identity
        for (value in values) result = operator.applyAsInt(result, value)
        return result
    }

    public fun anyMatch(predicate: IntPredicate): Boolean {
        for (value in values) if (predicate.test(value)) return true
        return false
    }

    public fun allMatch(predicate: IntPredicate): Boolean {
        for (value in values) if (!predicate.test(value)) return false
        return true
    }

    public fun noneMatch(predicate: IntPredicate): Boolean = !anyMatch(predicate)

    public companion object {
        public fun of(vararg values: Int): IntStream = IntStream(values.copyOf())
        public fun empty(): IntStream = IntStream(IntArray(0))

        public fun range(startInclusive: Int, endExclusive: Int): IntStream {
            if (startInclusive >= endExclusive) return empty()
            val result = mutableListOf<Int>()
            var value = startInclusive
            while (value < endExclusive) {
                result.add(value)
                value++
            }
            return of(*result.toIntArray())
        }

        public fun rangeClosed(startInclusive: Int, endInclusive: Int): IntStream {
            if (startInclusive > endInclusive) return empty()
            val result = mutableListOf<Int>()
            var value = startInclusive
            while (true) {
                result.add(value)
                if (value == endInclusive) break
                value++
            }
            return of(*result.toIntArray())
        }
    }
}
