// KUU-2036: accessing a later singleton must initialize it before loading state.
var initialized = 0
fun mark(value: Int): Int { initialized += 1; return value }
class Consumer {
    fun constant(): Int = Point.CONSTANT
    fun north(): Int = Point.NORTH.x
    fun chain(): Int = Chain.value
}
data class Point(val x: Int) {
    companion object {
        const val CONSTANT = 9
        // Explicit types isolate initialization guards from KUU-2056 inference.
        val NORTH: Point = Point(mark(-1))
    }
}
object Chain { val value: Int = Later.value + 1 }
object Later { val value: Int = mark(41) }
object Unused { val value = mark(-100) }
fun Companion(): Int = 7
fun main() {
    val consumer = Consumer()
    println(initialized)
    println(consumer.constant())
    println(initialized)
    println(consumer.north())
    println(initialized)
    println(consumer.north())
    println(initialized)
    println(consumer.chain())
    println(initialized)
    println(Later.value)
    println(initialized)
    try { println(Failing.value) } catch (e: Throwable) { println("caught") }
    println(Companion())
}
object Failing { val value: Int = error("boom") }
