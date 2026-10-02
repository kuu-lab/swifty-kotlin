fun main() {
    val values: MutableList<Int> = mutableListOf(1, 2, 1)
    println(values.remove(1))
    println(values)
    println(values.remove(3))
    println(values)
}
