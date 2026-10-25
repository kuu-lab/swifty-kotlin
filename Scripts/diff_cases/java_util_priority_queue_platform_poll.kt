// KUU-3373: Java PriorityQueue.poll has a platform return type at call sites.
import java.util.PriorityQueue

fun main() {
    val emptyInts = PriorityQueue<Int>()
    println("nullable-check:${emptyInts.poll() == null}")
    try {
        val value: Int = emptyInts.poll()
        println("unexpected:$value")
    } catch (e: NullPointerException) {
        println("npe:local")
    }
    try {
        println(PriorityQueue<Int>().poll() + 1)
    } catch (e: NullPointerException) {
        println("npe:unbox")
    }

    val emptyNullableInts = PriorityQueue<Int?>()
    val nullableValue: Int? = emptyNullableInts.poll()
    println("nullable-element:$nullableValue:${emptyNullableInts.size}")
}
