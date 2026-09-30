fun acceptUIntRangeProgression(range: UIntProgression): Boolean = true

fun acceptUIntRangeClosedRange(range: ClosedRange<UInt>): Boolean = true

fun acceptUIntRangeCompanion(companion: Any): Boolean = true

fun main() {
    val range = UIntRange(1u, 2u)
    println(acceptUIntRangeProgression(range))
    println(acceptUIntRangeClosedRange(range))
    println(acceptUIntRangeCompanion(UIntRange.Companion))

    val asProgression: UIntProgression = range
    println(asProgression)
    println(asProgression == UIntRange(1u, 2u))
}
