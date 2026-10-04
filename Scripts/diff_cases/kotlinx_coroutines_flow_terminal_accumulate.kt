import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    val source = flowOf(1, 2, 3)
    val folded = source.runningFold(10) { acc, value -> acc + value }
    println(folded.toList())
    println(folded.toList())
    val scanned = source.scan(0) { acc, value -> acc + value }
    println(scanned.toList())
    println(scanned.toList())
    val reduced = source.runningReduce { acc, value -> acc + value }
    println(reduced.toList())
    println(reduced.toList())
    println(emptyFlow<Int>().runningFold(7) { acc, value -> acc + value }.toList())
    println(emptyFlow<Int>().runningReduce { acc, value -> acc + value }.toList())
    println(flowOf(8).runningReduce { acc, value -> acc + value }.toList())
    println(source.runningFold("x") { acc, value -> acc + value }.toList())
    println(flowOf<Int?>(null, 2, null).runningReduce { acc, value -> (acc ?: 0) + (value ?: 0) }.toList())
}
