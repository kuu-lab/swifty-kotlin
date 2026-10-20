fun main() {
    val source = intArrayOf(-2147483648, 0, 2147483647)
    val copy = source.toList()
    source[0] = 7
    println(copy)
    println(intArrayOf().toList())
    println(intArrayOf(1).toList())
    println(arrayOf("control").toList())
}
