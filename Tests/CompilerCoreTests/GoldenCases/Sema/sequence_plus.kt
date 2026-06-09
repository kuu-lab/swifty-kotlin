fun main() {
    val s1 = sequenceOf(1, 2, 3)
    val s2 = sequenceOf(4, 5, 6)

    // plus(other: Sequence<T>): Sequence<T>
    val combined = s1.plus(s2)
    println(combined.toList())

    // operator + syntax
    val combined2 = s1 + s2
    println(combined2.toList())

    // plusElement(element: T): Sequence<T>
    val withElement = s1.plusElement(99)
    println(withElement.toList())
}
