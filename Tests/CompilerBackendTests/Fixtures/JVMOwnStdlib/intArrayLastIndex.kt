fun last(values: IntArray): Int = values.lastIndex
fun main() {
    println(intArrayOf().lastIndex)
    println(intArrayOf(7).lastIndex)
    println(last(intArrayOf(1, 2, 3)))
    val values = intArrayOf(8, 9)
    println(values[values.lastIndex])
    println(values.size)
}
