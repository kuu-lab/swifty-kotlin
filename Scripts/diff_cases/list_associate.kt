fun main() {
    val numbers = listOf(1, 2, 3, 4)
    println(numbers.associate { (it % 2) to (it * 10) })

    val words = listOf("apple", "banana", "cherry")
    println(words.associate { it.first() to it.length })

    val single = listOf(42)
    println(single.associate { (it - 40) to (it + 1) })

    val empty = emptyList<Int>()
    println(empty.associate { it to it })

    println(numbers.filter { it > 2 }.associate { it to (it * 3) })
}
