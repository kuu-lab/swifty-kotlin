// KUU-1306: source-backed selectors use the erased function-value ABI.
data class SearchEntry(val key: Int)

fun entryKey(entry: SearchEntry): Int = entry.key

fun main() {
    val numbers = listOf(1, 3, 5, 7)
    println(numbers.binarySearchBy(5) { it })
    println(numbers.binarySearchBy(4) { it })
    println(numbers.binarySearchBy(5, 1) { it })
    println(numbers.binarySearchBy(5, 1, 3) { it })
    println(numbers.binarySearchBy(5, fromIndex = 0, toIndex = 2, selector = { it }))
    val offset = 10
    println(numbers.binarySearchBy(15) { it + offset })
    val selector: (Int) -> Int = { it + offset }
    println(numbers.binarySearchBy(15, selector = selector))
    println(listOf(SearchEntry(1), SearchEntry(3), SearchEntry(5)).binarySearchBy(3, selector = ::entryKey))
    println(listOf(1L, 3L, 5L).binarySearchBy(3L) { it })
    println(listOf(1.0, 3.0, 5.0).binarySearchBy(3.0) { it })
    println(listOf("a", "bb", "ccc").binarySearchBy("bb") { it })
    println(listOf("a", "bb", "ccc").binarySearchBy(2) { it.length })
    println(emptyList<Int>().binarySearchBy(5) { it })
    println(numbers.binarySearchBy(5, 2, 2) { it })
    try {
        numbers.binarySearchBy(5) { throw IllegalStateException("selector") }
    } catch (e: IllegalStateException) {
        println("selector threw")
    }
}
