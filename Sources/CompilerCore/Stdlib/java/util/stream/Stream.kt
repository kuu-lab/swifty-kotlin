package java.util.stream

import java.util.Comparator
import java.util.function.Consumer
import java.util.function.Function
import java.util.function.Predicate
import java.util.function.ToDoubleFunction
import java.util.function.ToIntFunction
import java.util.function.ToLongFunction

public class Stream<T> private constructor(private val values: List<T>) {
    public fun filter(predicate: Predicate<T>): Stream<T> =
        Stream(values.filter { predicate.test(it) })

    public fun <R> map(mapper: Function<T, R>): Stream<R> =
        Stream(values.map { mapper.apply(it) })

    public fun <R> flatMap(mapper: Function<T, Stream<R>>): Stream<R> {
        val result = mutableListOf<R>()
        for (value in values) for (mapped in mapper.apply(value).values) result.add(mapped)
        return Stream(result)
    }

    public fun distinct(): Stream<T> = Stream(values.distinct())

    public fun sorted(comparator: Comparator<in T>): Stream<T> = Stream(values.sortedWith(comparator))

    public fun peek(action: Consumer<T>): Stream<T> {
        for (value in values) action.accept(value)
        return this
    }

    public fun limit(maxSize: Long): Stream<T> {
        if (maxSize < 0) throw IllegalArgumentException("Max size must be non-negative")
        if (maxSize >= values.size.toLong()) return this
        return Stream(values.take(maxSize.toInt()))
    }

    public fun skip(count: Long): Stream<T> {
        if (count < 0) throw IllegalArgumentException("Skip count must be non-negative")
        if (count >= values.size.toLong()) return empty()
        return Stream(values.drop(count.toInt()))
    }

    public fun forEach(action: Consumer<T>) {
        for (value in values) action.accept(value)
    }

    public fun forEachOrdered(action: Consumer<T>) = forEach(action)
    public fun count(): Long = values.size.toLong()
    public fun anyMatch(predicate: Predicate<T>): Boolean = values.any { predicate.test(it) }
    public fun allMatch(predicate: Predicate<T>): Boolean = values.all { predicate.test(it) }
    public fun noneMatch(predicate: Predicate<T>): Boolean = values.none { predicate.test(it) }
    public fun toList(): List<T> = values.toMutableList()

    public fun <A, R> collect(collector: Collector<T, A, R>): R = collector.collect(values)

    public fun collect(collector: ListCollector): List<T> = values.toMutableList()

    public fun reduce(identity: T, accumulator: java.util.function.BinaryOperator<T>): T {
        var result = identity
        for (value in values) result = accumulator.apply(result, value)
        return result
    }

    public fun mapToInt(mapper: ToIntFunction<T>): IntStream {
        val result = IntArray(values.size)
        var index = 0
        for (value in values) {
            result[index] = mapper.applyAsInt(value)
            index++
        }
        return IntStream.of(*result)
    }

    public fun mapToLong(mapper: ToLongFunction<T>): LongStream {
        val result = LongArray(values.size)
        var index = 0
        for (value in values) {
            result[index] = mapper.applyAsLong(value)
            index++
        }
        return LongStream.of(*result)
    }

    public fun mapToDouble(mapper: ToDoubleFunction<T>): DoubleStream {
        val result = DoubleArray(values.size)
        var index = 0
        for (value in values) {
            result[index] = mapper.applyAsDouble(value)
            index++
        }
        return DoubleStream.of(*result)
    }

    public companion object {
        public fun <T> of(vararg values: T): Stream<T> = Stream(values.toList())

        public fun <T> empty(): Stream<T> = Stream(emptyList())

        internal fun <T> fromIterable(values: Iterable<T>): Stream<T> = Stream(values.toList())
    }
}
