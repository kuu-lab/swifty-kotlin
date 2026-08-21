// Diff regression for kotlin.Pair receiver members.
fun main() {
    val pair = Pair(1, "one")
    val copied = pair.copy()
    val firstChanged = pair.copy(first = 2)
    val secondChanged = pair.copy(second = "two")
    val bothChanged = pair.copy(3, "three")

    println(pair.first)
    println(pair.second)
    println(pair.component1())
    println(pair.component2())
    println(copied)
    println(firstChanged)
    println(secondChanged)
    println(bothChanged)
}
