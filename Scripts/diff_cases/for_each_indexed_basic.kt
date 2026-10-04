fun main() {
    val values = listOf("a", "bb", "ccc")
    values.forEachIndexed { index, value ->
        println("$index=$value")
    }
    val numbers = listOf(3, 1, 2)
    var sum = 0
    numbers.forEachIndexed { index, value -> sum += index * value }
    println(sum)
    val empty = listOf<Int>()
    empty.forEachIndexed { index, value -> println(index + value) }
    println("done")
}
