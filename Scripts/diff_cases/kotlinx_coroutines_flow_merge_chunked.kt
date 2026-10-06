import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.flow.*
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds

fun main() = runBlocking {
    // flattenConcat is sequential upstream, so the order is deterministic.
    println(flowOf(flowOf(1, 2), flowOf(3, 4)).flattenConcat().toList())
    println(flowOf(flowOf(1), emptyFlow<Int>(), flowOf(2)).flattenConcat().toList())
    println(emptyFlow<Flow<Int>>().flattenConcat().toList())
    try {
        flowOf(flowOf(1)).flattenMerge(0).toList()
    } catch (e: IllegalArgumentException) {
        println("flattenMerge(0)")
    }
    // concurrency == 1 degenerates to flattenConcat on JVM, so it is deterministic.
    println(flowOf(flowOf(1, 2), flowOf(3, 4)).flattenMerge(1).toList())
    // merge order is unspecified upstream; compare order-insensitively.
    println(listOf(flowOf(1, 2)).merge().toList())
    println(listOf(flowOf(1, 2), flowOf(3, 4)).merge().toList().sorted())
    println(merge(flowOf(1), flowOf(2), flowOf(3)).toList().sorted())

    println(flowOf(1, 2, 3, 4, 5).chunked(2).toList())
    println(flowOf(1, 2).chunked(5).toList())
    println(emptyFlow<Int>().chunked(2).toList())
    try {
        flowOf(1).chunked(0).toList()
    } catch (e: IllegalArgumentException) {
        println("chunked(0)")
    }

    // Single-element flows produce the same emissions in the sequential
    // snapshot model as JVM combineTransform. The transforms are bound through
    // explicitly-typed vals: a lambda literal cannot yet be checked against a
    // FlowCollector-receiver parameter at a call site (builder-inference gap).
    val pairSum: suspend FlowCollector<Int>.(Int, Int) -> Unit = { a, b -> emit(a + b) }
    println(flowOf(1).combineTransform(flowOf(2), pairSum).toList())
    val pairTwice: suspend FlowCollector<Int>.(Int, Int) -> Unit = { a, b -> emit(0); emit(a + b) }
    println(flowOf(1).combineTransform(flowOf(2), pairTwice).toList())
    val pairDash: suspend FlowCollector<String>.(Int, Int) -> Unit = { a, b -> emit("$a-$b") }
    println(flowOf(1, 2).combineTransform(flowOf(3), pairDash).toList().sorted())
    println(combineTransform(flowOf(1), flowOf(2), pairSum).toList())
    val tripleSum: suspend FlowCollector<Int>.(Int, Int, Int) -> Unit = { a, b, c -> emit(a + b + c) }
    println(combineTransform(flowOf(1), flowOf(2), flowOf(3), tripleSum).toList())
    val quadSum: suspend FlowCollector<Int>.(Int, Int, Int, Int) -> Unit =
        { a, b, c, d -> emit(a + b + c + d) }
    println(combineTransform(flowOf(1), flowOf(2), flowOf(3), flowOf(4), quadSum).toList())
    val quintSum: suspend FlowCollector<Int>.(Int, Int, Int, Int, Int) -> Unit =
        { a, b, c, d, e -> emit(a + b + c + d + e) }
    println(combineTransform(flowOf(1), flowOf(2), flowOf(3), flowOf(4), flowOf(5), quintSum).toList())
    val arraySum: suspend FlowCollector<Int>.(Array<Int>) -> Unit = { values -> emit(values.sum()) }
    println(combineTransform(flowOf(1), flowOf(2), transform = arraySum).toList())
    println(combineTransform(listOf(flowOf(1), flowOf(2)), arraySum).toList())

    println(intArrayOf(1, 2).asFlow().toList())
    println(longArrayOf(3L, 4L).asFlow().toList())
    println(arrayOf(5, 6).asFlow().toList())
    println(listOf(7, 8).iterator().asFlow().toList())
    println(sequenceOf(9).asFlow().toList())

    try {
        flow<Int> {
            emit(1)
            kotlinx.coroutines.delay(200)
            emit(2)
        }.timeout(50.milliseconds).toList()
    } catch (e: TimeoutCancellationException) {
        println("timed out")
    }
    try {
        flowOf(1).timeout(Duration.ZERO).toList()
    } catch (e: TimeoutCancellationException) {
        println("immediate")
    }
    println(flowOf(1, 2).timeout(10.milliseconds).toList())
}
