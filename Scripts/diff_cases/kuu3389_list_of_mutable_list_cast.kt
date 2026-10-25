fun main() {
    println(listOf(1) is MutableList<*>)
    println(listOf(1) as MutableList<*>)

    val erased: Any = listOf(1)
    println(erased is MutableList<*>)
    println(erased as MutableList<*>)
    println(mutableListOf(1) is List<*>)

    try {
        (erased as MutableList<Int>).add(2)
        println("mutable")
    } catch (_: UnsupportedOperationException) {
        println("read-only")
    }
}
