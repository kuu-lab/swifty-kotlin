fun main() {
    val strings = arrayOf("a", "b")
    for (index in strings.indices) println(strings[index])
    val ints = intArrayOf(7, 8)
    for (index in ints.indices) println(ints[index])
    val empty = emptyArray<String>().indices
    println(empty.first)
    println(empty.last)
    println(empty.isEmpty())
    for (index in emptyArray<String>().indices) println("unexpected")
    for (index in intArrayOf().indices) println("unexpected")
    println(strings.size)
    println(ints[1])
}
