fun main() {
    val list = listOf(1, 2, 3)
    println(list.joinToString())
    println(list.joinToString(" | "))
    println(list.joinToString(prefix = "<", postfix = ">"))
    println(list.joinToString(separator = ":", prefix = "[", postfix = "]"))
    println(list.joinToString { (it * 10).toString() })
    println(list.joinToString(",") { (it * 10).toString() })
    println(list.joinToString(",", "[", "]") { (it * 10).toString() })

    val strings = "a\r\nbb\r\nccc".split("\r\n")
    println(strings.joinToString(",") { it.length.toString() })

    val iter: Iterable<Int> = list
    println(iter.joinToString("-") { (it * 2).toString() })
}
