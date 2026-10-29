import java.util.function.IntFunction
import java.util.function.IntPredicate
import java.util.function.IntUnaryOperator
import java.util.function.Predicate
import java.util.stream.IntStream

fun main() {
    var calls = 0
    val stream = IntStream.of(65, 66, 67).map(IntUnaryOperator { calls++; it })
    println("before=$calls")
    println("first=" + stream.findFirst().getAsInt())
    println("after=$calls")

    var mapCalls = 0
    var filterCalls = 0
    val ordered = IntStream.of(1, 2, 3)
        .map(IntUnaryOperator { mapCalls++; it * 2 })
        .filter(IntPredicate { filterCalls++; it == 4 })
        .map(IntUnaryOperator { mapCalls++; it + 1 })
    println("ordered-before=$mapCalls,$filterCalls")
    println("ordered=" + ordered.findFirst().getAsInt())
    println("ordered-after=$mapCalls,$filterCalls")

    var matchCalls = 0
    val found = IntStream.of(65, 66, 67).anyMatch(IntPredicate { matchCalls++; it == 66 })
    println("any=$found,calls=$matchCalls")

    var emptyCalls = 0
    val emptyCount = IntStream.empty().map(IntUnaryOperator { emptyCalls++; it }).count()
    println("empty=$emptyCount,calls=$emptyCalls")

    var exceptionCalls = 0
    val throwing = IntStream.of(1, 2, 3).map(IntUnaryOperator {
        exceptionCalls++
        if (it == 2) throw IllegalStateException("boom")
        it
    })
    println("exception-before=$exceptionCalls")
    try {
        throwing.toArray()
        println("exception=missing")
    } catch (_: IllegalStateException) {
        println("exception=thrown")
    }
    println("exception-after=$exceptionCalls")

    var boxedCalls = 0
    val boxed = IntStream.of(10, 20, 30)
        .map(IntUnaryOperator { boxedCalls++; it })
        .boxed()
    println("boxed-before=$boxedCalls")
    println("boxed-any=" + boxed.anyMatch(Predicate<Int> { it == 10 }))
    println("boxed-after=$boxedCalls")

    var objectCalls = 0
    val objects = IntStream.of(1, 2, 3).mapToObj(IntFunction<String> {
        objectCalls++
        "value:$it"
    })
    println("object-before=$objectCalls")
    println("object-any=" + objects.anyMatch(Predicate<String> { it == "value:1" }))
    println("object-after=$objectCalls")

    val original = IntStream.of(1, 2)
    val derived = original.map(IntUnaryOperator { it })
    try {
        original.count()
        println("parent-reuse=allowed")
    } catch (_: IllegalStateException) {
        println("parent-reuse=illegal")
    }
    println("derived-count=" + derived.count())
    try {
        derived.count()
        println("terminal-reuse=allowed")
    } catch (_: IllegalStateException) {
        println("terminal-reuse=illegal")
    }
}
