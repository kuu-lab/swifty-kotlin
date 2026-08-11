fun main() {
    println(Pair(1, "x") == Pair(1, "x"))
    println(Pair(1, "x") == Pair(2, "x"))
    println(Pair(1, "x") == Pair(1, "y"))
    println(Pair(1, "x").hashCode() == Pair(1, "x").hashCode())
    val nullableA: Pair<Int?, String?> = Pair(null, null)
    val nullableB: Pair<Int?, String?> = Pair(null, null)
    println(nullableA == nullableB)
    println(Pair(1, "x").equals(null))

    println(Triple(1, "x", true) == Triple(1, "x", true))
    println(Triple(1, "x", true) == Triple(1, "x", false))
    println(Triple(1, "x", true).hashCode() == Triple(1, "x", true).hashCode())

    println(Pair(Pair(1, 2), 3) == Pair(Pair(1, 2), 3))
    println(Pair(Pair(1, 2), 3) == Pair(Pair(1, 9), 3))

    println(setOf(Pair(1, 2), Pair(1, 2), Pair(3, 4)).size)
    println(setOf(Triple(1, 2, 3), Triple(1, 2, 3)).size)
    println(listOf(Pair(1, 2), Pair(3, 4)).contains(Pair(3, 4)))
    println(listOf(Pair(1, 2)).indexOf(Pair(1, 2)))
    println(mapOf(Pair(1, 2) to "v")[Pair(1, 2)])
    println(listOf(1 to "a", 1 to "a").distinct().size)
}
