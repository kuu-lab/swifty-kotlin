package diff

fun main() {
    val direct: LongRange = LongRange.EMPTY
    val explicit: LongRange = LongRange.Companion.EMPTY
    println(direct.start)
    println(direct.endInclusive)
    println(explicit.start)
    println(explicit.endInclusive)
    println(direct.isEmpty())
    println(explicit.isEmpty())
}
