package golden.sema

@RequiresOptIn
annotation class Marker

annotation class PlainMarker

// Annotation classes are not ordinary values in Kotlin; cover the markerClass
// vararg surface through a valid OptIn annotation use.
@OptIn(Marker::class, PlainMarker::class)
fun markerClassUse(): Int = 1
