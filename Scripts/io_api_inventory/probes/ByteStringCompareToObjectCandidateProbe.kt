package kotlinx.io.bytestring.probe

import kotlinx.io.bytestring.ByteString

private fun bytes(vararg values: Int): ByteString =
    ByteString(ByteArray(values.size) { index -> values[index].toByte() })

private fun compareThroughComparable(left: Comparable<ByteString>, right: ByteString): Int =
    left.compareTo(right)

private fun compare(name: String, left: ByteString, right: ByteString, expected: Int) {
    val typed = left.compareTo(right)
    val erased = compareThroughComparable(left, right)
    check(typed == expected) { "$name typed result: $typed" }
    check(erased == typed) { "$name Comparable result: $erased" }
    println("compare:$name=$erased")
}

fun main() {
    compare("empty", bytes(), bytes(), 0)
    compare("equal", bytes(1, 2, 3), bytes(1, 2, 3), 0)
    compare("prefix", bytes(1, 2), bytes(1, 2, 3), -1)
    compare("lexicographic", bytes(0, 1, 2), bytes(0, 1, 3), -1)
    compare("longer", bytes(1, 2, 3), bytes(1, 2), 1)
    compare("first-byte", bytes(1, 2, 3), bytes(0, 1, 2), 1)
    compare("unsigned-high", bytes(0xff), bytes(0), 1)
    compare("unsigned-low", bytes(1), bytes(0x81), -1)
}
