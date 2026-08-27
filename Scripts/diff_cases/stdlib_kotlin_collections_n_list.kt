var evaluations = 0

fun nextNullable(value: Int): Int? {
    evaluations++
    return if (value > 0) value else null
}

fun main() {
    // A singleton list accepts nullable elements and has a fresh identity.
    val single: List<Int> = listOf(7)
    val nullable: List<String?> = listOf<String?>(null)
    println(single)
    println(single.size)
    println(nullable)
    println(listOf(1) === listOf(1))

    // The single-element overload filters one nullable value without
    // evaluating the argument more than once.
    println(listOfNotNull<Any>(null))
    println(listOfNotNull(42))
    println(listOfNotNull(nextNullable(1)))
    println(evaluations)

    // Keep the existing vararg overload covered separately.
    println(listOfNotNull(1, null, 2))
}
