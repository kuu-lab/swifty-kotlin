package diff

@kotlin.RequiresOptIn
annotation class DefaultMarker

@kotlin.RequiresOptIn("warning", kotlin.RequiresOptIn.Level.WARNING)
annotation class WarningMarker

fun main() {
    println("ok")
}
