fun main() {
    val list: List<Int?> = listOf(1, null, 3)
    val array: Array<Int?> = arrayOf(1, null, 3)

    println(list.joinToString("|", "<", ">", 2, "..."))
    println(array.joinToString("|", "<", ">", 2, "..."))
    println(list.joinToString("|", "<", ">", 2, "...") { it.toString() })
    println(array.joinToString("|", "<", ">", 2, "...") { it.toString() })

    val listBuffer = StringBuilder()
    list.joinTo(listBuffer, "|", "<", ">", 2, "...")
    println(listBuffer)

    val arrayBuffer = StringBuilder()
    array.joinTo(arrayBuffer, "|", "<", ">", 2, "...") { it.toString() }
    println(arrayBuffer)

    println(emptyList<Int>().joinToString("|", "<", ">", 2, "..."))
    println(emptyArray<Int>().joinToString("|", "<", ">", 2, "..."))
}
