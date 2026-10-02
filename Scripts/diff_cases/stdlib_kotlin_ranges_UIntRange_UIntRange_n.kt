fun main() {
    val range = 2u..6u
    val same = 2u..6u
    val empty = UIntRange.EMPTY

    println("properties=${range.start},${range.endInclusive},${range.endExclusive}")
    println("range=$range")
    println("equal=${range == same},hash=${range.hashCode() == same.hashCode()}")
    println("empty=${empty.isEmpty()},emptyHash=${empty.hashCode()},emptyString=$empty")
}
