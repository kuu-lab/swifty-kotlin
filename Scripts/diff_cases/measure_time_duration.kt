import kotlin.time.measureTime

fun main() {
    val duration = measureTime {
        var sum = 0
        for (i in 1..1000) sum += i
    }
    println(duration.inWholeMilliseconds >= 0)
}
