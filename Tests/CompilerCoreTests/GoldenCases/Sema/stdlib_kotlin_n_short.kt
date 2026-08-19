package golden.sema

fun main() {
    val empty = shortArrayOf()
    val values = shortArrayOf(1, -2, 32767, -32768)
    println(empty.size)
    println(values.size)
    println(values[0])
    println(values[1])
    println(values[2])
    println(values[3])
}
