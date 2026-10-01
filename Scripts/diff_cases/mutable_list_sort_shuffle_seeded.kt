import kotlin.random.Random

fun main() {
    val numbers = mutableListOf(5, 2, 4, 1, 3)
    numbers.sortBy { it % 3 }
    println(numbers)
    numbers.sortByDescending { it % 3 }
    println(numbers)

    val words = mutableListOf("pear", "fig", "apple")
    words.sortWith(compareBy { it.length })
    println(words)
    words.reverse()
    println(words)
    words.shuffle(Random(7))
    println(words)

    val empty = mutableListOf<Int>()
    empty.shuffle(Random(7))
    empty.reverse()
    println(empty)
}
