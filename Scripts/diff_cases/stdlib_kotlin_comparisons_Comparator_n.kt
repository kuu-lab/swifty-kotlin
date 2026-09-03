import kotlin.comparisons.then
import kotlin.comparisons.thenDescending

private var secondaryCalls = 0
private var descendingCalls = 0

fun main() {
    val primary = Comparator<Int> { a, b -> a.compareTo(b) }
    val secondary = Comparator<Any> { _, _ ->
        secondaryCalls += 1
        7
    }
    val combined = primary.then(secondary)
    println(combined.compare(1, 2))
    println(secondaryCalls)
    println(combined.compare(2, 2))
    println(secondaryCalls)

    val minComparator = Comparator<Any> { _, _ ->
        descendingCalls += 1
        Int.MIN_VALUE
    }
    val descending = primary.thenDescending(minComparator)
    println(descending.compare(2, 1))
    println(descendingCalls)
    println(descending.compare(1, 1))
    println(descendingCalls)

    val nullablePrimary = Comparator<String?> { _, _ -> 0 }
    val nullableSecondary = Comparator<Any?> { _, _ -> 9 }
    println(nullablePrimary.then(nullableSecondary).compare(null, null))
    println(nullablePrimary.thenDescending(nullableSecondary).compare(null, null))
}
