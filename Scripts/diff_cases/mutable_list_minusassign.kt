fun main() {
    val list = mutableListOf(1, 2, 3, 4)
    list -= 2
    println(list)
    list -= listOf(1, 4)
    println(list)

    val other = mutableListOf(10, 20)
    other -= 99
    println(other)

    val typed: MutableList<Int> = mutableListOf(5, 6, 7)
    typed -= 6
    println(typed)
}
