
fun main() {
    // IntRange / IntProgression have no direct toIntArray() -- must go through toList() first.
    println((1..7).toList().toIntArray().joinToString(" "))
    println((1..7 step 2).toList().toIntArray().joinToString(" "))

    // LongRange / LongProgression have no direct toLongArray().
    println((1L..7L).toList().toLongArray().joinToString(" "))
    println((1L..7L step 2).toList().toLongArray().joinToString(" "))

    // UIntRange / UIntProgression have no direct toUIntArray().
    println((1u..7u).toList().toUIntArray().joinToString(" "))
    println((1u..7u step 2).toList().toUIntArray().joinToString(" "))

    // ULongRange / ULongProgression have no direct toULongArray().
    println((1uL..7uL).toList().toULongArray().joinToString(" "))
    println((1uL..7uL step 2).toList().toULongArray().joinToString(" "))
}
