fun main() {
    val values = UByteArray(4) { (it + 1).toUByte() }
    println(values.size)
    println(values[0])
    println(values[3])

    val empty = UByteArray(0) { 255.toUByte() }
    println(empty.size)
}
