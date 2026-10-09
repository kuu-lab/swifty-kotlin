fun <T : Comparable<T>> coerceToBounds(value: T, minimum: T, maximum: T): T =
    value.coerceAtLeast(minimum).coerceAtMost(maximum)

fun main() {
    println(UIntRange.Companion.EMPTY.isEmpty())

    val chars = CharProgression.fromClosedRange('a', 'e', 2)
    println("${chars.first()} ${chars.last()} ${chars.step}")

    println(coerceToBounds(5, 1, 4))
    println(coerceToBounds("delta", "echo", "zulu"))

    val closed = "a".."z"
    println(closed)
    println(closed == ("a".."z"))
    println(closed == ("a".."y"))

    val openEnd = "a"..<"z"
    println(openEnd)
}
