fun main() {
    val values: Array<out Int> = arrayOf(1, 2)
    values.sortBy { -it }
    println(values.toList())
    println(arrayOf(2, 1).sortedByDescending { it })
    println(arrayOf("a", "bb", "c").sortedByDescending { if (it.length == 1) null else it.length })
}
