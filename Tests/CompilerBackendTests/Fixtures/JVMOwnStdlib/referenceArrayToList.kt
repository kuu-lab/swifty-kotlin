fun main() {
    val source = arrayOf<String?>("a", null, "b")
    val copy = source.toList()
    source[0] = "changed"
    println(copy)
    println(arrayOf("one").toList())
    println(emptyArray<String>().toList())
    println(arrayOf(arrayOf("nested")).toList()[0][0])
    println(listOf(1, 2).toList())
}
