import java.util.function.DoublePredicate
import java.util.function.LongPredicate
import java.util.function.ToDoubleFunction
import java.util.function.ToLongFunction
import java.util.stream.DoubleStream
import java.util.stream.LongStream
import java.util.stream.Stream

fun main() {
    val longs = LongStream.of(1L, 2L, 3L)
    var calls = 0
    val filtered = longs.filter(LongPredicate { calls++; it > 1L })
    println("long-before=$calls")
    try { longs.sum(); println("long-parent=accepted") }
    catch (e: IllegalStateException) { println("long-parent=rejected") }
    println("long-first=${filtered.findFirst().getAsLong()}")
    println("long-calls=$calls")
    try { filtered.count(); println("long-child=accepted") }
    catch (e: IllegalStateException) { println("long-child=rejected") }

    val doubles = DoubleStream.of(1.5, 2.5)
    val boxed = doubles.boxed()
    try { doubles.sum(); println("double-parent=accepted") }
    catch (e: IllegalStateException) { println("double-parent=rejected") }
    println("boxed-count=${boxed.count()}")
    try { boxed.count(); println("boxed-reuse=accepted") }
    catch (e: IllegalStateException) { println("boxed-reuse=rejected") }

    val longConverted = Stream.of("a", "bb").mapToLong(ToLongFunction<String> { it.length.toLong() })
    println("long-sum=${longConverted.sum()}")
    try { longConverted.sum(); println("long-reuse=accepted") }
    catch (e: IllegalStateException) { println("long-reuse=rejected") }

    var doubleCalls = 0
    val doubleConverted = Stream.of("a", "bb").mapToDouble(ToDoubleFunction<String> { it.length.toDouble() })
        .filter(DoublePredicate { doubleCalls++; it > 0.0 })
    println("double-before=$doubleCalls")
    println("double-first=${doubleConverted.findFirst().getAsDouble()}")
    println("double-calls=$doubleCalls")
    try { doubleConverted.count(); println("double-reuse=accepted") }
    catch (e: IllegalStateException) { println("double-reuse=rejected") }

    val empty = LongStream.empty()
    println("empty-present=${empty.min().isPresent()}")
    try { empty.max(); println("empty-reuse=accepted") }
    catch (e: IllegalStateException) { println("empty-reuse=rejected") }

    val validAfterLongError = LongStream.of(4L)
    try { validAfterLongError.limit(-1L); println("long-limit=accepted") }
    catch (e: IllegalArgumentException) { println("long-limit=rejected") }
    println("long-after-limit=${validAfterLongError.sum()}")
    val validAfterDoubleError = DoubleStream.of(4.5)
    try { validAfterDoubleError.skip(-1L); println("double-skip=accepted") }
    catch (e: IllegalArgumentException) { println("double-skip=rejected") }
    println("double-after-skip=${validAfterDoubleError.sum()}")
}
