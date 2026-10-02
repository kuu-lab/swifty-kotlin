fun acceptUIntProgressionCompanion(companion: Any): Boolean = true

fun main() {
    println(acceptUIntProgressionCompanion(UIntProgression.Companion))
    println(UIntProgression.fromClosedRange(1u, 5u, 2).toList())
}
