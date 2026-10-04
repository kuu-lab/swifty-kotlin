// KSP-1542/BUG-166: Collection<T>/MutableCollection<T>/Iterable<T>-typed
// receivers must dispatch isEmpty/contains/iterator/add/remove/retainAll
// through the interface member (kk_op_contains, __kk_collection_*,
// __kk_mutable_collection_*, kk_list_iterator/kk_iterable_iterator) instead of
// requiring itable virtual dispatch, even when the runtime box behind the
// receiver is a Set rather than a List.
fun main() {
    val c: Collection<Int> = setOf(1, 2, 3)
    println(c.isEmpty())
    println(c.contains(2))
    println(c.contains(99))
    println(c.containsAll(listOf(1, 3)))
    var sum = 0
    val it = c.iterator()
    while (it.hasNext()) {
        sum += it.next()
    }
    println(sum)

    val emptyC: Collection<Int> = emptySet()
    println(emptyC.isEmpty())

    val mc: MutableCollection<Int> = mutableSetOf(1, 2, 3)
    println(mc.add(4))
    println(mc.remove(2))
    println(mc.retainAll(listOf(1, 3, 4)))
    println(mc.size)
    mc.clear()
    println(mc.isEmpty())

    val iter: Iterable<Int> = setOf(10, 20, 30)
    var total = 0
    for (x in iter) {
        total += x
    }
    println(total)
    val iter2 = iter.iterator()
    println(iter2.hasNext())
}
