fun main() {
    val values: Sequence<Int> = sequenceOf(1, 2, 3, 4)
    println(values.firstNotNullOfOrNull<String> { value ->
        if (value == 3) "three" else null
    })

    val missing: Sequence<Int> = sequenceOf(1, 2)
    val result = missing.firstNotNullOfOrNull<String> { _ -> null }
    println(result ?: "missing")
}
