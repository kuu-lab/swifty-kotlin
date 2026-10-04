fun main() {
    val empty = LongArray(0)
    val values = LongArray(4) { index -> index.toLong() + 10L }
    println(empty.size)
    println(values.size)
    println(values[0])
    println(values[3])
}
