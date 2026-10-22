fun main() {
    val list = mutableListOf(1, 2, 3, 4, 5, 6)
    list -= 2..4
    println(list)
    list += 8..9
    println(list)
    list += 7
    list -= 1
    list += listOf(10, 11)
    list -= setOf(10)
    list += arrayOf(20)
    list += sequenceOf(21)
    println(list)

    val set = mutableSetOf(1, 2, 3)
    set += 5..6
    set -= 2..3
    set += 9
    set -= 9
    println(set)

    val collection: MutableCollection<Int> = mutableListOf(1, 2, 3)
    collection += 5..6
    collection -= 1..2
    println(collection)
}
