fun nonLocalReturnFromAny(): Int {
    listOf(1, 2, 3).any { if (it == 2) return 20; false }
    return -1
}

fun main() {
    val values = listOf(1, 2, 3)
    val iterable: Iterable<Int> = values
    val collection: Collection<Int> = values
    val lazyIterable: Iterable<Int> = sequenceOf(1, 2, 3).asIterable()

    println(values.any { it > 2 })
    println(iterable.none { it > 5 })
    println(collection.all { it > 0 })
    println(lazyIterable.any { it == 2 })
    println(values.any { it > 5 })
    println(iterable.all { it < 3 })
    println(collection.none { it == 2 })
    println(emptyList<Int>().any { it > 0 })
    println(emptyList<Int>().all { it > 0 })
    println(emptyList<Int>().none { it > 0 })

    println(values.any())
    println(emptyList<Int>().any())
    println(values.none())
    println(emptyList<Int>().none())

    var anyCalls = 0
    println(values.any { anyCalls++; it == 2 })
    println(anyCalls)
    var allCalls = 0
    println(values.all { allCalls++; it < 2 })
    println(allCalls)
    var noneCalls = 0
    println(values.none { noneCalls++; it == 2 })
    println(noneCalls)
    println(nonLocalReturnFromAny())
}
