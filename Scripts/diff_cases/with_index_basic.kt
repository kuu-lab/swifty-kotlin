fun main() {
    val values = listOf("a", "bb", "ccc")
    for ((index, value) in values.withIndex()) {
        println("$index:$value")
    }
    for (entry in values.withIndex()) {
        println(entry.index)
        println(entry.value)
    }
    val single = IndexedValue(7, "x")
    println(single.index)
    println(single.value)
    println(single.component1())
    println(single.component2())
    println(single)
    println(IndexedValue(7, "x") == single)
    println(listOf(single))
    val empty = listOf<Int>()
    println(empty.withIndex().count())
}
