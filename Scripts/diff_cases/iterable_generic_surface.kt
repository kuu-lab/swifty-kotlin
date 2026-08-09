// KSP-435: generic Iterable<T> surface reached through an interface-typed
// receiver, so it must go through the bundled Kotlin implementations rather
// than a List-specific runtime bridge.
fun <T> describe(values: Iterable<T>) {
    println(values.any())
    println(values.toMutableList().size)
    println(values.toMutableSet().size)
    println(values.toHashSet().size)
    println(values.joinToString(", "))
    println(values.joinToString("|") { "<" + it.toString() + ">" })
    println(values.joinTo(StringBuilder("seed:"), "-", "[", "]").toString())
    println(values.last().toString())
    println(values.asSequence().toList().size)
}

fun requireNoNullsRoundTrip(values: Iterable<String?>) {
    val checked = values.requireNoNulls()
    println(checked.joinToString(","))
    println(checked.any { it == "y" })
}

fun main() {
    describe(listOf(1, 2, 3))
    describe(setOf(4, 5))

    val numbers: Iterable<Int> = listOf(1, 2, 3, 4)
    println(numbers.all { it > 0 })
    println(numbers.all { it > 2 })
    println(numbers.firstNotNullOf { if (it > 2) "big:$it" else null })
    println(numbers.firstNotNullOfOrNull { if (it > 9) "big:$it" else null })

    val destination = mutableListOf(0)
    println(numbers.toCollection(destination) === destination)
    println(destination)

    val deduped = listOf(1, 1, 2).toCollection(mutableSetOf<Int>())
    println(deduped)

    requireNoNullsRoundTrip(listOf("x", "y"))

    try {
        listOf<String?>("x", null).requireNoNulls().joinToString(",")
    } catch (e: IllegalArgumentException) {
        println("requireNoNulls threw")
    }

    try {
        emptyList<Int>().last()
    } catch (e: NoSuchElementException) {
        println("last threw")
    }
}
