import kotlin.system.measureTimeMicros

fun useMeasureTimeMicros(): Long = measureTimeMicros {
    val x = 1 + 2
}
