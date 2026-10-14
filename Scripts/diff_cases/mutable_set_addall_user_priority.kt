// KUU-2154: source overloads retain Kotlin member/extension priority.
fun MutableSet<Int>.addAll(elements: Iterable<String>): Boolean {
    println("user-iterable:${elements.count()}")
    return false
}
fun MutableSet<Int>.addAll(elements: Sequence<String>): Boolean {
    println("user-sequence:${elements.count()}")
    return false
}
fun MutableSet<Int>.addAll(elements: Any): Boolean {
    println("user-any")
    return false
}
class OwnBulkSet : AbstractMutableSet<Int>() {
    val backing = mutableSetOf<Int>()
    override val size: Int get() = backing.size
    override fun iterator(): MutableIterator<Int> = backing.iterator()
    override fun add(element: Int): Boolean = backing.add(element)
    fun addAll(elements: Iterable<Int>): Boolean {
        println("member-iterable:${elements.count()}")
        return false
    }
    fun addAll(elements: Sequence<Int>): Boolean {
        println("member-sequence:${elements.count()}")
        return false
    }
}
fun main() {
    val set: MutableSet<Int> = mutableSetOf<Int>()
    val words: Iterable<String> = listOf("a", "b")
    println(set.addAll(words))
    println(set.addAll(sequenceOf("x")))
    val values: Iterable<Int> = listOf(1, 2)
    println(set.addAll(values))
    println(set.addAll(sequenceOf(2, 3)))
    println(set.size)
    val concrete = HashSet<Int>()
    println(concrete.addAll(words))
    println(concrete.addAll(sequenceOf("x")))
    val custom = OwnBulkSet()
    println(custom.addAll(values))
    println(custom.addAll(sequenceOf(4)))
    println(custom.size)
}
