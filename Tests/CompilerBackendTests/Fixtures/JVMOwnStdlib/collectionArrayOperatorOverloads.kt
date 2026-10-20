fun main() {
    val list = listOf(1, 2, 2, 3)
    val extra = arrayOf(2, 4, 4)
    println(list + extra); println(list.plus(extra).size)
    println(list - arrayOf(2, 3)); println(list.minus(arrayOf(2, 3)).size)
    val collection: Collection<Int> = list
    println(collection + extra)
    val iterable: Iterable<Int> = list
    println(iterable + extra); println(iterable - arrayOf(2, 3))
    println(list + emptyArray<Int>()); println(list - emptyArray<Int>())
    println(list); println(extra.toList())
    val set = setOf(3, 1, 2)
    val added: Set<Int> = set + arrayOf(2, 4, 4, 0)
    val removed: Set<Int> = set - arrayOf(3, 2, 2)
    println(added); println(removed); println(set)
    println(emptySet<Int>() + arrayOf(2, 2, 1))
    val nullable = listOf<Int?>(null, 1, null, 2)
    println(nullable - arrayOf<Int?>(null, 2))
    println(nullable + arrayOf<Int?>(null, 3))
    val primitive = intArrayOf(2, 3)
    val scalarArray: List<Any> = listOf(1) + primitive
    println(scalarArray.size)
    val nested: List<Array<Int>> = listOf(arrayOf(1)).plus<Array<Int>>(arrayOf(2, 3))
    println(nested.size); println(nested[1].toList())
    val map = mapOf(1 to "a", 2 to "b", 3 to "c")
    println(map - arrayOf(2, 3)); println(map.minus(arrayOf(9)))
    println(map - emptyArray<Int>()); println(map)
}
