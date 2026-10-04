fun main() {
    val p = Pair(1, "hello")
    println(p)
    println(p.first)
    println(p.second)
    println(p.component1())
    println(p.component2())
    println(p.toList())

    val t = Triple("a", 2, true)
    println(t)
    println(t.first)
    println(t.second)
    println(t.third)
    println(t.component1())
    println(t.component2())
    println(t.component3())
    println(t.toList())

    val (x, y) = Pair(10, 20)
    println(x + y)
    val (i, s, b) = Triple(1, "two", false)
    println("$i $s $b")

    val nested = Pair(Pair(1, 2), Triple(3, 4, 5))
    println(nested)
    println(nested.first.second)
    println(nested.second.third)

    val nullable: Pair<Int?, String?> = Pair(null, null)
    println(nullable)
    println(nullable.first)
    println(nullable.toList())

    val pairs = listOf(1, 2, 3).map { Pair(it, it * it) }
    println(pairs)
    println(pairs.map { it.second }.sum())
}
