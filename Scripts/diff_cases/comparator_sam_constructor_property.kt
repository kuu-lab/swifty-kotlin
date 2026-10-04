// KSP-CAP-005: the Comparator SAM constructor (and any generic call with a
// trailing lambda) used to have its trailing lambda silently dropped when
// used as a top-level or class-member property initializer, because the
// parser split the lambda into a separate CST node that the property
// head-token extraction stopped at. The remaining `Comparator < Int >`
// tokens then re-parsed as a chained comparison instead of a call, so the
// property's type came out as `Boolean` instead of `Comparator<Int>`.
val topLevelComparator = Comparator<Int> { a, b -> a - b }
val topLevelFromFactory = compareBy<Int> { it % 5 }

class Box {
    val memberComparator = Comparator<Int> { a, b -> b - a }
}

fun main() {
    println(topLevelComparator.compare(3, 5))
    println(topLevelFromFactory.compare(7, 2))
    println(Box().memberComparator.compare(3, 5))

    val list = listOf(5, 3, 4, 1, 2)
    println(list.sortedWith(topLevelComparator))
    println(list.sortedWith(Box().memberComparator))
}
