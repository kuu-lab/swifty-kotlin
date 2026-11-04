// KUU-3962: JVM `setOf(e)` is the unmodifiable `Collections.singleton` — its
// iterator is a `MutableIterator` whose `remove()` throws
// `UnsupportedOperationException` instead of mutating. `setOf(e1, e2)`,
// `setOf(e1, e1)` and spread calls keep a mutable `LinkedHashSet` backing.
private fun <T> probe(name: String, s: Set<T>) {
    val it = s.iterator()
    if (it.hasNext()) it.next()
    try {
        (it as MutableIterator<T>).remove()
        println(name + ":removed:" + s)
    } catch (e: Throwable) {
        println(name + ":caught:" + e::class.simpleName + ":" + s)
    }
}

fun main() {
    probe("setOf1", setOf(1))
    probe("setOf12", setOf(1, 2))
    probe("setOf11", setOf(1, 1))
    probe("setOf0", setOf<Int>())
    probe("emptySet", emptySet<Int>())
    probe("setOfSpread1", setOf(*arrayOf(1)))
    probe("setOfSpread0", setOf(*emptyArray<Int>()))
    probe("mutableSetOf1", mutableSetOf(1))
    probe("setOfNotNull1", setOfNotNull(1))
    probe("setOfNotNullSpread1", setOfNotNull(*arrayOf(1)))

    val l = listOf(1)
    val lit = l.iterator()
    if (lit.hasNext()) lit.next()
    try {
        (lit as MutableIterator<Int>).remove()
        println("listOf1:removed:" + l)
    } catch (e: Throwable) {
        println("listOf1:caught:" + e::class.simpleName + ":" + l)
    }
    val elit = emptyList<Int>().iterator()
    try {
        (elit as MutableIterator<Int>).remove()
        println("emptyList:removed")
    } catch (e: Throwable) {
        println("emptyList:caught:" + e::class.simpleName)
    }

    val m = mapOf(1 to 2)
    val mit = m.entries.iterator()
    if (mit.hasNext()) mit.next()
    try {
        (mit as MutableIterator<MutableMap.MutableEntry<Int, Int>>).remove()
        println("mapOf1:removed:" + m)
    } catch (e: Throwable) {
        println("mapOf1:caught:" + e::class.simpleName + ":" + m)
    }
    val m2 = mapOf(1 to 2, 3 to 4)
    val mit2 = m2.entries.iterator()
    if (mit2.hasNext()) mit2.next()
    try {
        (mit2 as MutableIterator<MutableMap.MutableEntry<Int, Int>>).remove()
        println("mapOf2:removed:" + m2)
    } catch (e: Throwable) {
        println("mapOf2:caught:" + e::class.simpleName + ":" + m2)
    }
}
