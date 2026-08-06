import kotlin.system.measureNanoTime
import kotlin.system.measureTimeMillis

fun main() {
    // KSP-617: kotlin.system public layer backed by __kk_system_* bridges.
    val millis = measureTimeMillis {
        var sum = 0
        for (i in 1..1000) sum += i
        println(sum)
    }
    println(millis >= 0L)

    val nanos = measureNanoTime {
        var sum = 0L
        for (i in 1..1000) sum += i.toLong()
        println(sum)
    }
    println(nanos >= 0L)

    val start = System.currentTimeMillis()
    val end = System.currentTimeMillis()
    println(start > 0L)
    println(end >= start)

    val t1 = System.nanoTime()
    val t2 = System.nanoTime()
    println(t2 >= t1)
}
