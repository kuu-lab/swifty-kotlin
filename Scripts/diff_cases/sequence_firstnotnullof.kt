fun main() {
    val values = sequenceOf(1, 2, 3, 4)
    println(values.firstNotNullOf<String> { value ->
        if (value == 3) "three" else null
    })

    try {
        val empty: Sequence<Int> = sequenceOf(1, 2)
        empty.firstNotNullOf<String> { _ -> null }
        println("unreachable")
    } catch (e: NoSuchElementException) {
        println("missing")
    }
}
