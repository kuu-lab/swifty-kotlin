package golden.sema

fun main() {
    val empty = intArrayOf()
    val values = intArrayOf(1, -2, 2147483647)
    println(empty.size)
    println(values.size)
    println(values[0])
    println(values[1])
    println(values[2])
}
