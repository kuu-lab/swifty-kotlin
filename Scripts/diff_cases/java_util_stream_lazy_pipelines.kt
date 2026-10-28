import java.util.function.Consumer
import java.util.function.Function
import java.util.function.IntFunction
import java.util.function.IntUnaryOperator
import java.util.function.LongPredicate
import java.util.function.ToDoubleFunction
import java.util.function.ToIntFunction
import java.util.function.ToLongFunction
import java.util.stream.IntStream
import java.util.stream.Stream

fun main() {
    val events = mutableListOf<String>()
    val ordered = Stream.of(1, 2, 3, 4)
        .peek(Consumer<Int> { events.add("peek$it") })
        .map(Function<Int, Int> { events.add("map$it"); it * 10 })
        .filter(java.util.function.Predicate<Int> { events.add("filter$it"); it > 25 })
        .limit(1)
    println("pipeline-before=${events.size}")
    println("pipeline=${ordered.toList()}")
    println("pipeline-events=${events.joinToString(",")}")

    var exceptionCalls = 0
    val safe = Stream.of(1, 2, 3)
        .map(Function<Int, Int> {
            exceptionCalls++
            if (it == 2) throw IllegalStateException("deferred")
            it
        })
        .limit(1)
    println("exception-before=$exceptionCalls")
    safe.forEach(Consumer<Int> {})
    println("exception-limited=$exceptionCalls")

    val throwing = Stream.of(1, 2, 3).map(Function<Int, Int> {
        exceptionCalls++
        if (it == 2) throw IllegalStateException("deferred")
        it
    })
    try {
        throwing.forEach(Consumer<Int> {})
        println("exception-after=none")
    } catch (_: IllegalStateException) {
        println("exception-after=thrown/$exceptionCalls")
    }

    var intCalls = 0
    val ints = Stream.of(1, 2, 3).mapToInt(ToIntFunction<Int> { intCalls++; it * 2 })
    println("int-before=$intCalls")
    println("int-sum=${ints.sum()}")
    println("int-after=$intCalls")

    var longCalls = 0
    val longs = Stream.of(1, 2, 3).mapToLong(ToLongFunction<Int> { longCalls++; it.toLong() })
    println("long-before=$longCalls")
    println("long-sum=${longs.sum()}")
    println("long-after=$longCalls")

    var doubleCalls = 0
    val doubles = Stream.of(1, 2, 3).mapToDouble(ToDoubleFunction<Int> { doubleCalls++; it / 2.0 })
    println("double-before=$doubleCalls")
    println("double-sum=${doubles.sum()}")
    println("double-after=$doubleCalls")

    var shortCalls = 0
    val firstEven = Stream.of(1, 2, 3, 4)
        .mapToLong(ToLongFunction<Int> { shortCalls++; it.toLong() })
        .filter(LongPredicate { it % 2L == 0L })
        .limit(1)
        .sum()
    println("short-circuit=$firstEven/$shortCalls")

    var boxedCalls = 0
    val boxed = IntStream.of(65, 66, 67)
        .map(IntUnaryOperator { boxedCalls++; it })
        .boxed()
        .limit(1)
    println("boxed-before=$boxedCalls")
    println("boxed=${boxed.toList()}/$boxedCalls")

    var objectCalls = 0
    val objects = IntStream.of(7, 8, 9)
        .mapToObj(IntFunction<String> { objectCalls++; "v$it" })
        .limit(1)
    println("mapToObj-before=$objectCalls")
    println("mapToObj=${objects.toList()}/$objectCalls")

    var longBoxCalls = 0
    val boxedLongs = Stream.of(5, 6, 7)
        .mapToLong(ToLongFunction<Int> { longBoxCalls++; it.toLong() })
        .boxed()
        .limit(1)
    println("long-boxed-before=$longBoxCalls")
    println("long-boxed=${boxedLongs.toList()}/$longBoxCalls")
}
