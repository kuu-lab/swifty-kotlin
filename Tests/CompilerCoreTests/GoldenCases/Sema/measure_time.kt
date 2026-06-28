import kotlin.system.measureNanoTime
import kotlin.system.measureTimeMicros
import kotlin.system.measureTimeMillis

fun useMeasureNanoTime(): Long = measureNanoTime {
    val x = 1 + 2
}

fun useMeasureTimeMicros(): Long = measureTimeMicros {
    val x = 1 + 2
}

fun useMeasureTimeMillis(): Long = measureTimeMillis {
    val x = 1 + 2
}
