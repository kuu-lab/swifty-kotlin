import sort.*
fun main() {
    val values = arrayOf(9, 1, 5, 3, 7, 1)
    quickSort(values, 0, values.lastIndex)
    println(values.joinToString(","))
}
