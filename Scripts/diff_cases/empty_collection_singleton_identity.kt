fun main() {
    println(emptyList<Int>() === emptyList<Int>())
    println(emptySet<Int>() === emptySet<Int>())
    println(emptyMap<Int, Int>() === emptyMap<Int, Int>())
    println(listOf<Int>() === listOf<Int>())
    println(setOf<Int>() === setOf<Int>())
    println(mapOf<Int, Int>() === mapOf<Int, Int>())
    println("".toList() === "".toList())
    println(listOf(1).drop(1) === listOf(2).drop(1))
}
