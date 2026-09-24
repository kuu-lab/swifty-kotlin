package diff

fun main() {
    val direct: ULongRange = ULongRange.EMPTY
    val explicit: ULongRange = ULongRange.Companion.EMPTY
    println(direct.isEmpty())
    println(explicit.isEmpty())
}
