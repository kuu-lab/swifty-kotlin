package golden.sema

@kotlin.ExperimentalUnsignedTypes
annotation class MyUnsignedMarker

@MyUnsignedMarker
fun experimentalUnsigned(): Int = 42

@OptIn(kotlin.ExperimentalUnsignedTypes::class)
fun caller(): Int = experimentalUnsigned()
