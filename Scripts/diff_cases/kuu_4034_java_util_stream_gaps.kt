import java.util.function.DoublePredicate
import java.util.function.DoubleUnaryOperator
import java.util.function.IntPredicate
import java.util.function.IntUnaryOperator
import java.util.function.LongPredicate
import java.util.function.LongUnaryOperator
import java.util.function.ToIntFunction
import java.util.stream.Collectors
import java.util.stream.DoubleStream
import java.util.stream.IntStream
import java.util.stream.LongStream
import java.util.stream.Stream

fun main() {
    // Collectors.joining returns Collector<CharSequence, ?, String>; it must be
    // accepted by Stream<T>.collect for any T that is a CharSequence subtype.
    println("join=" + Stream.of("a", "b").collect(Collectors.joining(",")))
    println("join-empty-delim=" + Stream.of("a", "b").collect(Collectors.joining()))
    println("join-fix=" + Stream.of("a", "b").collect(Collectors.joining(",", "[", "]")))
    println("join-single=" + Stream.of("x").collect(Collectors.joining(", ")))
    println("join-none=" + "'" + Stream.empty<String>().collect(Collectors.joining(",")) + "'")
    println("join-builder=" + Stream.of(StringBuilder("x"), StringBuilder("y")).collect(Collectors.joining("+")))

    // IntStream.iterate(seed, next) is an infinite lazy stream.
    println("iterate=" + IntStream.iterate(1) { it * 2 }.limit(5).toArray().toList())
    println("iterate-sum=" + IntStream.iterate(0, IntUnaryOperator { it + 3 }).limit(4).sum())
    // Java 9+ iterate(seed, hasNext, next) follows for-loop semantics.
    println("iterate3=" + IntStream.iterate(1, IntPredicate { it < 100 }, IntUnaryOperator { it * 3 }).toArray().toList())
    println("iterate3-edge=" + IntStream.iterate(3, IntPredicate { it < 5 }, IntUnaryOperator { it + 1 }).toArray().toList())
    println("iterate3-empty=" + IntStream.iterate(1, IntPredicate { it < 0 }, IntUnaryOperator { it }).count())

    // toArray on an iterate-derived and a plain IntStream.
    println("toArray=" + IntStream.iterate(5) { it - 1 }.limit(10).toArray().toList())
    println("toArray-plain=" + IntStream.of(3, 1).toArray().toList())

    // mapToInt accepts a bare lambda (SAM conversion to ToIntFunction).
    println("mapToInt=" + Stream.of("ab", "c").mapToInt { it.length }.sum())
    println("mapToInt-explicit=" + Stream.of("ab", "c").mapToInt(ToIntFunction<String> { it.length }).toArray().toList())

    // iterate on the remaining stream kinds.
    println("stream-iterate=" + Stream.iterate(1) { it * 2 }.limit(4).toList())
    println("stream-iterate3=" + Stream.iterate(1, { it < 10 }, { it + 2 }).toList())
    println("long-iterate=" + LongStream.iterate(1L) { it * 3 }.limit(4).toArray().toList())
    println("long-iterate3=" + LongStream.iterate(1L, LongPredicate { it < 10L }, LongUnaryOperator { it * 2L }).toArray().toList())
    println("double-iterate=" + DoubleStream.iterate(1.0) { it * 0.5 }.limit(3).toArray().toList())
    println("double-iterate3=" + DoubleStream.iterate(0.5, DoublePredicate { it < 10.0 }, DoubleUnaryOperator { it * 4.0 }).toArray().toList())
}
