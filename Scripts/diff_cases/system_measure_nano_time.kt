import kotlin.system.measureNanoTime

fun main() {
    var sum = 0L
    val elapsed = measureNanoTime {
        for (i in 1..1000) sum += i
    }
    println(elapsed >= 0)
    println(sum == 500500L)
}
