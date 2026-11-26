// DIFF_JVM
// DIFF_SKIP_NATIVE: JVM-lane regression for the JVM stdlib declaration surface.
class FirstLetterGrouping(val values: List<String>) : Grouping<String, String> {
    override fun sourceIterator(): Iterator<String> = values.iterator()
    override fun keyOf(element: String): String = element.substring(0, 1)
}

fun main() {
    val grouping = FirstLetterGrouping(listOf("apple", "banana", "avocado"))
    val destination = mutableMapOf("a" to 10)
    val result = grouping.eachCountTo(destination)
    println(result)
    println(destination)
    println(result === destination)
}
