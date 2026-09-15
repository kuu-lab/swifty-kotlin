fun acceptLongProgressionCompanion(companion: Any): Boolean = true

fun main() {
    println(acceptLongProgressionCompanion(LongProgression.Companion))
    println(LongProgression.fromClosedRange(1L, 5L, 2).toList())
}
