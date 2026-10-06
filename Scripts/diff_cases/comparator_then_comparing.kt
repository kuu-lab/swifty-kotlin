// KUU-1302: JVM-compatible binary-lambda comparator composition.
fun main() {
    val natural = naturalOrder<Int>()
    println(natural.thenComparing { x, y -> 0 }.compare(1, 1))

    var calls = 0
    val offset = 7
    val secondary = natural.thenComparing { a, b ->
        calls += 1
        a - b + offset
    }
    println(secondary.compare(1, 2))
    println(secondary.compare(2, 1))
    println(calls)
    println(secondary.compare(1, 1))
    println(calls)

    val tied = Comparator<Int> { a, b -> 0 }
    val descending = tied.thenComparing { a, b -> b - a }
    println(descending.compare(1, 3))
    println(descending.compare(3, 1))
    println(descending.compare(2, 2))
    println(descending.thenComparing { a, b -> 9 }.compare(2, 2))
    println(descending.reversed().compare(1, 3))
    println(tied.thenComparator { a, b -> b - a }.compare(1, 3))
    println(tied.thenComparing(descending).compare(1, 3))
    println(natural.thenComparing(descending).compare(1, 3))
}
