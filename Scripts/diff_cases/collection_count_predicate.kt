fun main() {
    val values: Collection<Int> = listOf(0, 1, 2)
    println(values.count { it % 2 == 0 })
}
