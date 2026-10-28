import java.util.function.IntBinaryOperator
import java.util.function.IntPredicate
import java.util.function.IntUnaryOperator
import java.util.stream.IntStream

fun main() {
    val terminal = IntStream.of(1, 2)
    println(terminal.count())
    try {
        println(terminal.sum())
    } catch (e: IllegalStateException) {
        println("terminal-used")
    }

    val source = IntStream.of(2, 3)
    val mapped = source.map(IntUnaryOperator { it * 2 })
    try {
        println(source.count())
    } catch (e: IllegalStateException) {
        println("source-used")
    }
    println(mapped.sum())
    try {
        println(mapped.count())
    } catch (e: IllegalStateException) {
        println("mapped-used")
    }

    println(IntStream.of(2, 4).average().getAsDouble())
    println(IntStream.empty().findAny().isPresent())

    val filterSource = IntStream.of(1, 2, 3, 4)
    val filtered = filterSource.filter(IntPredicate { it % 2 == 0 })
    try {
        filterSource.map(IntUnaryOperator { it + 1 })
        println("filter-source:accepted")
    } catch (e: IllegalStateException) {
        println("filter-source:used")
    }
    val doubled = filtered.map(IntUnaryOperator { it * 3 })
    try {
        println(filtered.sum())
    } catch (e: IllegalStateException) {
        println("filtered:used")
    }
    println(doubled.reduce(0, IntBinaryOperator { first, second -> first + second }))
    try {
        println(doubled.anyMatch(IntPredicate { it == 6 }))
    } catch (e: IllegalStateException) {
        println("reduced:used")
    }
    println(IntStream.empty().allMatch(IntPredicate { it > 0 }))
    println(IntStream.empty().noneMatch(IntPredicate { it > 0 }))
    println(IntStream.empty().average().isPresent())
}
