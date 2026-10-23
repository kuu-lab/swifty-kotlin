// KUU-2918: Collection.contains bridges return false for an incompatible erased value.
class MySet<K, V, E : Map.Entry<K, V>> : AbstractSet<E>() {
    override fun contains(element: E): Boolean = element.key !== null
    override val size: Int get() = 0
    override fun isEmpty(): Boolean = false
    override fun containsAll(elements: Collection<E>) = false
    override fun iterator(): Iterator<E> = TODO()
}

private class TestEntry<K, V>(
    override val key: K,
    override val value: V
) : Map.Entry<K, V>

fun main() {
    val set = MySet<Int, Int, Map.Entry<Int, Int>>()
    println(set.contains(object {} as Any?))

    val erased: Collection<Any?> = set
    println(erased.contains(object {} as Any?))
    println(erased.contains(TestEntry(1, 2)))
}
