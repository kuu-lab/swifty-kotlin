class HashKey(val id: Int, val limit: Int = 1) {
    var calls = 0
    override fun hashCode(): Int {
        calls += 1
        if (calls > limit) throw IllegalStateException("extra hash")
        return 7
    }
}
fun singletonRemoval(kind: Int) {
    val key = HashKey(1)
    val missing = HashKey(2)
    val source = mapOf(key to (null as String?))
    try {
        val result: Map<HashKey, String?> = when (kind) {
            0 -> source - emptyList<HashKey>()
            1 -> source - emptyArray<HashKey>()
            2 -> source - emptySequence<HashKey>()
            else -> source - missing
        }
        println(result.size)
        println(result.values.iterator().next() == null)
    } catch (e: IllegalStateException) { println(e.message) }
    println(key.calls)
    println(missing.calls)
    println(source.size)
}
fun main() {
    singletonRemoval(0); singletonRemoval(1); singletonRemoval(2); singletonRemoval(3)
    val removed = HashKey(3, 2)
    println((mapOf(removed to 1) - removed).size)
    println(removed.calls)
    val first = HashKey(4, 10); val second = HashKey(5, 10)
    val source = mapOf(first to 1, second to 2)
    first.calls = 0; second.calls = 0
    println((source - emptyList<HashKey>()).size)
    println(first.calls); println(second.calls)
}
