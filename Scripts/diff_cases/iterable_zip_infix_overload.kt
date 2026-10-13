fun main() {
    println((listOf(1, 2) zip listOf(3, 4)).joinToString())
    println((listOf(1, 2) zip listOf(3, 4, 5)).joinToString())
    println(listOf(1, 2, 3).zip(listOf(4, 5)).joinToString())
    println(listOf(1, 2, 3).zip(listOf(4, 5)) { left, right -> "$left:$right" }.joinToString())
}
