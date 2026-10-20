fun main() {
    val values = arrayListOf("a", "b")
    values.add("c")
    println(values)
    println(values.removeAt(1))
    println(values[1])
    values[0] = "z"
    println(values[0])
    println(arrayListOf<String>().size)
    println(arrayListOf<String?>(null))
    val source = arrayOf("x", "y")
    val copy = arrayListOf(*source)
    source[0] = "changed"
    println(copy)
    println(mutableListOf(1, 2))
}
