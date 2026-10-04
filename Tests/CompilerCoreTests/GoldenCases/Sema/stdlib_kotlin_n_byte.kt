package golden.sema

fun main() {
    val empty = byteArrayOf()
    val values = byteArrayOf(1, -2, 127)
    println(empty.size)
    println(values.size)
    println(values[0])
    println(values[1])
}
