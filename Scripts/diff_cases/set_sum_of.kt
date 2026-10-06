// KUU-608: Set receivers must execute Iterable<T>.sumOf through the
// runtime-backed Set iterator, just like List receivers do.
fun main() {
    println(listOf(3, 1, 2).sumOf { it })
    println(setOf(3, 1, 2).sumOf { it })
}
