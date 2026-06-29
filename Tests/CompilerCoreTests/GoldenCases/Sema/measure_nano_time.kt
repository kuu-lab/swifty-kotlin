import kotlin.system.measureNanoTime

fun useMeasureNanoTime(): Long = measureNanoTime {
    val x = 1 + 2
}
