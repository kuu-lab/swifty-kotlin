fun main() {
    val values: Iterable<Int> = listOf(1, 2, 3, 4)
    println(values.firstNotNullOf<String> { value ->
        if (value == 2) "two" else null
    })

    try {
        val empty: Iterable<Int> = listOf(1, 2)
        empty.firstNotNullOf<String> { _ -> null }
        println("unreachable")
    } catch (e: NoSuchElementException) {
        println("missing")
    }
}
