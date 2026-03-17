import kotlin.system.measureTimeMillis
import kotlin.system.measureNanoTime

fun main() {
    val millis = measureTimeMillis {
        var sum = 0
        for (i in 1..1000) sum += i
        println(sum)
    }
    println(millis >= 0)
    val nanos = measureNanoTime {
        var sum = 0
        for (i in 1..1000) sum += i
    }
    println(nanos >= 0)
}
