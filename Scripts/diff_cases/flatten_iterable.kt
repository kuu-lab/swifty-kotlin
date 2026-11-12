fun <T> flattenGeneric(values: Iterable<Iterable<T>>): List<T> = values.flatten()

fun main() {
    println(listOf(listOf(1), listOf(2, 3)).flatten())
    println(flattenGeneric(listOf(emptyList<Int>(), listOf(4), emptyList(), listOf(5, 6))))
    println(flattenGeneric(listOf(emptyList<String>(), listOf("x"))))
}
