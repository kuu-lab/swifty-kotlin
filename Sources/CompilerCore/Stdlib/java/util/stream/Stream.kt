package java.util.stream

import java.util.Comparator
import java.util.function.Consumer
import java.util.function.Function
import java.util.function.Predicate
import java.util.function.ToDoubleFunction
import java.util.function.ToIntFunction
import java.util.function.ToLongFunction

public class Stream<T> private constructor(private val values: List<T>) {
    private var consumed: Boolean = false

    private fun consume(): List<T> {
        if (consumed) throw IllegalStateException("stream has already been operated upon or closed")
        consumed = true
        return values
    }

    public fun filter(predicate: Predicate<T>): Stream<T> {
        val source = consume()
        return Stream(source.filter { predicate.test(it) })
    }

    public fun <R> map(mapper: Function<T, R>): Stream<R> {
        val source = consume()
        return Stream(source.map { mapper.apply(it) })
    }

    public fun <R> flatMap(mapper: Function<T, Stream<R>>): Stream<R> {
        val source = consume()
        val result = mutableListOf<R>()
        for (value in source) for (mapped in mapper.apply(value).consume()) result.add(mapped)
        return Stream(result)
    }

    public fun distinct(): Stream<T> = Stream(consume().distinct())

    public fun sorted(comparator: Comparator<in T>): Stream<T> = Stream(consume().sortedWith(comparator))

    public fun peek(action: Consumer<T>): Stream<T> {
        val source = consume()
        for (value in source) action.accept(value)
        return Stream(source)
    }

    public fun limit(maxSize: Long): Stream<T> {
        if (maxSize < 0) throw IllegalArgumentException("Max size must be non-negative")
        val source = consume()
        if (maxSize >= source.size.toLong()) return Stream(source)
        return Stream(source.take(maxSize.toInt()))
    }

    public fun skip(count: Long): Stream<T> {
        if (count < 0) throw IllegalArgumentException("Skip count must be non-negative")
        val source = consume()
        if (count >= source.size.toLong()) return empty()
        return Stream(source.drop(count.toInt()))
    }

    public fun forEach(action: Consumer<T>) {
        for (value in consume()) action.accept(value)
    }

    public fun forEachOrdered(action: Consumer<T>) = forEach(action)
    public fun count(): Long = consume().size.toLong()
    public fun anyMatch(predicate: Predicate<T>): Boolean = consume().any { predicate.test(it) }
    public fun allMatch(predicate: Predicate<T>): Boolean = consume().all { predicate.test(it) }
    public fun noneMatch(predicate: Predicate<T>): Boolean = consume().none { predicate.test(it) }
    public fun toList(): List<T> = consume().toMutableList()

    public fun <A, R> collect(collector: Collector<T, A, R>): R = collector.collect(consume())

    public fun collect(collector: ListCollector): List<T> = consume().toMutableList()

    public fun reduce(identity: T, accumulator: java.util.function.BinaryOperator<T>): T {
        val source = consume()
        var result = identity
        for (value in source) result = accumulator.apply(result, value)
        return result
    }

    public fun mapToInt(mapper: ToIntFunction<T>): IntStream {
        val source = consume()
        val result = IntArray(source.size)
        var index = 0
        for (value in source) {
            result[index] = mapper.applyAsInt(value)
            index++
        }
        return IntStream.of(*result)
    }

    public fun mapToLong(mapper: ToLongFunction<T>): LongStream {
        val source = consume()
        val result = LongArray(source.size)
        var index = 0
        for (value in source) {
            result[index] = mapper.applyAsLong(value)
            index++
        }
        return LongStream.of(*result)
    }

    public fun mapToDouble(mapper: ToDoubleFunction<T>): DoubleStream {
        val source = consume()
        val result = DoubleArray(source.size)
        var index = 0
        for (value in source) {
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
