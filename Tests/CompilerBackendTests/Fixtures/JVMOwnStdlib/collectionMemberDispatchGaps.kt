fun main() {
    println(listOf(1, 2, 3).reduce { a, b -> a + b })
    println(listOf(1, 2, 3).subList(1, 3))
    println(mapOf("a" to 1).containsValue(1))
    println(listOf(4).getOrElse(0) { 99 })
    println(listOf(4).getOrElse(8) { it })
    println(mapOf("a" to 1).getOrElse("a") { 7 })
    println(mapOf("a" to 1).getOrElse("b") { 7 })
    val mutable = mutableMapOf("a" to 1)
    println(mutable.getOrPut("a") { 8 })
    println(mutable.getOrPut("b") { 8 })
    println(mutable)
    try {
        emptyList<Int>().reduce { a, b -> a + b }
        println("empty-reduce-missed")
    } catch (_: UnsupportedOperationException) {
        println("empty-reduce-threw")
    }
}
