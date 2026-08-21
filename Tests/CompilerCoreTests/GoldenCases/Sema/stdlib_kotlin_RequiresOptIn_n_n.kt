package golden.sema

@kotlin.RequiresOptIn
annotation class DefaultMarker

@kotlin.RequiresOptIn("warning", kotlin.RequiresOptIn.Level.WARNING)
annotation class WarningMarker

fun useMarkers() {}
