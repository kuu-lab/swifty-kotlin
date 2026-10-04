fun main() {
    val values = listOf(1, 2, 3)
    println(listOf("a" to 1, "b" to 2, "a" to 3).toMap())
    println(values.toSet())
    println(values.toHashSet())
    println(values.toMutableList())
    println(values.toMutableSet())

    val nullable: List<Int>? = null
    println(nullable.orEmpty())

    val (one, two, three, four, five) = listOf(10, 20, 30, 40, 50)
    println("$one,$two,$three,$four,$five")
    println(values.indices)
    println(values.lastIndex)
    println(values.isEmpty())
    println(values.isNotEmpty())
    println(emptyList<Int>().isEmpty())
    println(emptyList<Int>().isNotEmpty())

    val buffer = StringBuilder()
    println(values.joinTo(buffer, separator = "|", prefix = "<", postfix = ">"))
    println(values.joinToString(separator = ":", prefix = "[", postfix = "]"))
    println(values.joinToString("/") { (it * 2).toString() })
}
