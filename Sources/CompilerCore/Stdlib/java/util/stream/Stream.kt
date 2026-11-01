package java.util.stream

import java.util.Comparator
import java.util.function.Consumer
import java.util.function.Function
import java.util.function.Predicate
import java.util.function.ToDoubleFunction
import java.util.function.ToIntFunction
import java.util.function.ToLongFunction
import java.util.function.UnaryOperator

public class Stream<T> private constructor(private val values: Sequence<T>) {
    private var consumed: Boolean = false

    private fun consume(): Sequence<T> {
        if (consumed) throw IllegalStateException("stream has already been operated upon or closed")
        consumed = true
        return values
    }

    public fun filter(predicate: Predicate<T>): Stream<T> =
        Stream(consume().filter { predicate.test(it) })

    public fun <R> map(mapper: Function<T, R>): Stream<R> =
        Stream(consume().map { mapper.apply(it) })

    public fun <R> flatMap(mapper: Function<T, Stream<R>>): Stream<R> =
        Stream(consume().flatMap { mapper.apply(it).values })

    public fun distinct(): Stream<T> = Stream(consume().distinct())

    public fun sorted(comparator: Comparator<in T>): Stream<T> = Stream(consume().sortedWith(comparator))

    public fun peek(action: Consumer<T>): Stream<T> =
        Stream(consume().onEach { action.accept(it) })

    public fun limit(maxSize: Long): Stream<T> {
        if (maxSize < 0) throw IllegalArgumentException("Max size must be non-negative")
        return Stream(consume().streamLimit(maxSize))
    }

    public fun skip(count: Long): Stream<T> {
        if (count < 0) throw IllegalArgumentException("Skip count must be non-negative")
        return Stream(consume().streamSkip(count))
    }

    public fun forEach(action: Consumer<T>) {
        for (value in consume()) action.accept(value)
    }

    public fun forEachOrdered(action: Consumer<T>) = forEach(action)

    public fun count(): Long = consume().streamCount()

    public fun anyMatch(predicate: Predicate<T>): Boolean {
        for (value in consume()) if (predicate.test(value)) return true
        return false
    }

    public fun allMatch(predicate: Predicate<T>): Boolean {
        for (value in consume()) if (!predicate.test(value)) return false
        return true
    }

    public fun noneMatch(predicate: Predicate<T>): Boolean {
        for (value in consume()) if (predicate.test(value)) return false
        return true
    }

    public fun toList(): List<T> = consume().toMutableList()

    public fun <A, R> collect(collector: Collector<in T, A, R>): R = collector.collect(consume().toList())

    public fun collect(collector: ListCollector): List<T> = consume().toMutableList()

    public fun reduce(identity: T, accumulator: java.util.function.BinaryOperator<T>): T {
        var result = identity
        for (value in consume()) result = accumulator.apply(result, value)
        return result
    }

    public fun mapToInt(mapper: ToIntFunction<T>): IntStream =
        IntStream.fromSequence(consume().map { mapper.applyAsInt(it) })

    public fun mapToLong(mapper: ToLongFunction<T>): LongStream =
        LongStream.fromSequence(consume().map { mapper.applyAsLong(it) })

    public fun mapToDouble(mapper: ToDoubleFunction<T>): DoubleStream =
        DoubleStream.fromSequence(consume().map { mapper.applyAsDouble(it) })

    public companion object {
        public fun <T> of(vararg values: T): Stream<T> =
            Stream(streamSequence { values.iterator() })

        public fun <T> empty(): Stream<T> = Stream(streamSequence { emptyList<T>().iterator() })

        public fun <T> iterate(seed: T, next: UnaryOperator<T>): Stream<T> =
            Stream(streamSequence {
                object : Iterator<T> {
                    var current = seed

                    override fun hasNext(): Boolean = true

                    override fun next(): T {
                        val value = current
                        current = next.apply(value)
                        return value
                    }
                }
            })

        public fun <T> iterate(seed: T, hasNext: Predicate<in T>, next: UnaryOperator<T>): Stream<T> =
            Stream(streamSequence {
                object : Iterator<T> {
                    var current = seed
                    var first = true
                    var advanced = false
                    var valid = false

                    private fun advance() {
                        if (advanced) return
                        if (first) first = false
                        else current = next.apply(current)
                        valid = hasNext.test(current)
                        advanced = true
                    }

                    override fun hasNext(): Boolean {
                        advance()
                        return valid
                    }

                    override fun next(): T {
                        advance()
                        if (!valid) throw NoSuchElementException()
                        advanced = false
                        return current
                    }
                }
            })

        internal fun <T> fromIterable(values: Iterable<T>): Stream<T> =
            Stream(streamSequence { values.iterator() })

        internal fun <T> fromSequence(values: Sequence<T>): Stream<T> = Stream(values)
    }
}
