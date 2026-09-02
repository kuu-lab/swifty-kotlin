private class OneShotIterable<T>(private val values: List<T>) : Iterable<T> {
    private var consumed = false

    override fun iterator(): Iterator<T> {
        if (consumed) return emptyList<T>().iterator()
        consumed = true
        return values.iterator()
    }
}

private fun printFirstFailure(values: Iterable<Int>) {
    try {
        values.first()
        println("first-no-throw")
    } catch (e: NoSuchElementException) {
        println("first-empty")
    }
}

private fun printFirstPredicateFailure(values: Iterable<Int>) {
    try {
        values.first { it > 10 }
        println("first-predicate-no-throw")
    } catch (e: NoSuchElementException) {
        println("first-predicate-empty")
    }
}

private fun printFirstNotNullOfFailure(values: Iterable<Int>) {
    try {
        values.firstNotNullOf<Int, String> { null }
        println("first-not-null-no-throw")
    } catch (e: NoSuchElementException) {
        println("first-not-null-empty")
    }
}

private fun printPredicateException(values: Iterable<Int>) {
    try {
        values.firstOrNull {
            if (it == 2) throw IllegalStateException("predicate interrupted")
            false
        }
        println("predicate-no-throw")
    } catch (e: IllegalStateException) {
        println("predicate-interrupted")
    }
}

fun main() {
    val values: Iterable<Int> = OneShotIterable(listOf(1, 2, 3, 4))
    println(values.first())
    println(OneShotIterable(listOf(1, 2, 3, 4)).first { it > 2 })
    println(OneShotIterable(listOf(1, 2, 3, 4)).firstOrNull())
    println(OneShotIterable(listOf(1, 2, 3, 4)).firstOrNull { it > 2 })

    var transformCalls = 0
    val transformed = OneShotIterable(listOf(1, 2, 3, 4)).firstNotNullOf {
        transformCalls += 1
        if (it == 3) "hit" else null
    }
    println("$transformed/$transformCalls")

    var nullableTransformCalls = 0
    val transformedOrNull = OneShotIterable(listOf(1, 2, 3)).firstNotNullOfOrNull<Int, String> {
        nullableTransformCalls += 1
        null
    }
    println("${transformedOrNull ?: "null"}/$nullableTransformCalls")

    val nullableValues: Iterable<Int?> = OneShotIterable(listOf(null, 7))
    println(nullableValues.first() ?: "first-null")
    println(nullableValues.firstOrNull() ?: "first-or-null-null")
    println(OneShotIterable(listOf<Int?>(null, 7)).first { it == null } ?: "predicate-null")
    println(OneShotIterable(listOf<Int?>(null, 7)).firstOrNull { it == null } ?: "predicate-or-null-null")

    println(OneShotIterable(emptyList<Int>()).firstOrNull() ?: "empty-null")
    printFirstFailure(OneShotIterable(emptyList()))
    printFirstPredicateFailure(OneShotIterable(listOf(1, 2)))
    printFirstNotNullOfFailure(OneShotIterable(listOf(1, 2)))
    printPredicateException(OneShotIterable(listOf(1, 2, 3)))
}
