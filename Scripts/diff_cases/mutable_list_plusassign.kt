fun main() {
    val list = mutableListOf(1, 2)
    list += 3
    println(list)
    list += listOf(4, 5)
    println(list)

    val typed: MutableList<Int> = mutableListOf(9)
    typed += 8
    println(typed)
}
