fun main() {
    val values: Iterable<Int> = listOf(1, 2, 3, 4)
    println(values.firstNotNullOfOrNull<String> { value ->
        if (value == 2) "two" else null
    })

    val missing: Iterable<Int> = listOf(1, 2)
    val result = missing.firstNotNullOfOrNull<String> { _ -> null }
    println(result ?: "missing")
}
