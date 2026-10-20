fun additions(): Sequence<Int> = sequence {
    println("consume add")
    yield(2); yield(4); yield(4)
}
fun removals(): Sequence<Int> = sequence {
    println("consume remove")
    yield(2); yield(3); yield(2)
}
fun main() {
    val list = listOf(1, 2, 2, 3)
    val result = list + additions()
    println(result); println(result.size)
    println(list - removals())
    val iterable: Iterable<Int> = list
    println(iterable + sequenceOf(5, 5)); println(iterable - sequenceOf(2, 3))
    println(list + emptySequence<Int>()); println(list - emptySequence<Int>())
    val set = setOf(3, 1, 2)
    val added: Set<Int> = set + additions()
    val removed: Set<Int> = set - removals()
    println(added); println(removed); println(set)
    val nullable = listOf<Int?>(null, 1, null, 2)
    println(nullable - sequenceOf<Int?>(null, 2))
    println(nullable + sequenceOf<Int?>(null, 3))
}
