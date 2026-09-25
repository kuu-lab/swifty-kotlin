fun main() {
    val list = mutableListOf(1, 2, 3, 4)
    println(list.retainAll(listOf(2, 4)))
    println(list)
    println(list.retainAll(listOf(2, 4)))
    println(list)
    println(list.retainAll(emptyList()))
    println(list)
}
