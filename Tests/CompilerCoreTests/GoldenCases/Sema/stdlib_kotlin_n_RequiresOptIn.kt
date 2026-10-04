package golden.sema

@kotlin.RequiresOptIn(
    message = "experimental",
    level = kotlin.RequiresOptIn.Level.WARNING
)
annotation class MyMarker

@golden.sema.MyMarker
fun useMarker() {}
