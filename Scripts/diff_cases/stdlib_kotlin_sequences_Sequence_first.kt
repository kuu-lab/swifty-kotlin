fun firstNotNullValue(values: Sequence<Int>): String =
    values.firstNotNullOf { if (it > 1) "hit" else null }

fun firstNotNullValueOrNull(values: Sequence<Int>): String? =
    values.firstNotNullOfOrNull { if (it > 1) "hit" else null }

fun main() {
    val values = sequenceOf(1, 2, 3)
    println(firstNotNullValue(values))
    println(firstNotNullValueOrNull(values) ?: "missing")
    println(values.firstNotNullOfOrNull { null } ?: "missing")
    try {
        values.firstNotNullOf { null }
        println("unexpected")
    } catch (e: NoSuchElementException) {
        println("missing")
    }
}
