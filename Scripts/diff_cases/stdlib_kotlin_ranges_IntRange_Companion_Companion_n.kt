package diff

fun main() {
    val direct: IntRange = IntRange.EMPTY
    val explicit: IntRange = IntRange.Companion.EMPTY
    println(direct.start)
    println(direct.endInclusive)
    println(explicit.start)
    println(explicit.endInclusive)
    println(direct.isEmpty())
    println(explicit.isEmpty())
}
