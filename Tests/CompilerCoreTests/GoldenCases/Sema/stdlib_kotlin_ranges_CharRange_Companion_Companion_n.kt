package golden.sema

fun main() {
    val direct: CharRange = CharRange.EMPTY
    val explicit: CharRange = CharRange.Companion.EMPTY
    println(direct.start.code)
    println(direct.endInclusive.code)
    println(explicit.start.code)
    println(explicit.endInclusive.code)
    println(direct.isEmpty())
    println(explicit.isEmpty())
}
