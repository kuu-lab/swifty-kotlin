fun main() {
    val list = mutableListOf(1, 2)
    println(list.addAll(listOf(3, 4)))
    println(list)

    println(list.addAll(1, listOf(8, 9)))
    println(list)

    println(list.addAll(emptyList()))
    println(list.addAll(0, emptyList()))
    println(list)

    val collection: MutableCollection<Int> = mutableListOf(10)
    println(collection.addAll(listOf(11, 12)))
    println(collection)
}
