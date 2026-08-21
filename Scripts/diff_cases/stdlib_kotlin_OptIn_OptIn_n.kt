package diff

@RequiresOptIn
annotation class Marker

annotation class PlainMarker

@OptIn(Marker::class, PlainMarker::class)
fun markerClassUse(): Int = 1

fun main() {
    println("ok")
}
