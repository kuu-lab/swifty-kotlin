package diff

fun main() {
    val direct: UIntRange = UIntRange.EMPTY
    val explicit: UIntRange = UIntRange.Companion.EMPTY
    println(direct.isEmpty())
    println(explicit.isEmpty())
}
