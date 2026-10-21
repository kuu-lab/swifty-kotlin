abstract class BaseSet<E> : MutableSet<E> {
    override fun addAll(elements: Collection<E>): Boolean {
        println("BaseSet.addAll")
        return true
    }
    override fun retainAll(elements: Collection<E>): Boolean {
        println("BaseSet.retainAll")
        return true
    }
    override fun removeAll(elements: Collection<E>): Boolean {
        println("BaseSet.removeAll")
        return true
    }
}

class BuilderSet<E> : BaseSet<E>(), MutableSet<E> {
    private val backing = mutableSetOf<E>()
    override val size: Int get() = backing.size
    override fun isEmpty(): Boolean = backing.isEmpty()
    override fun contains(element: E): Boolean = backing.contains(element)
    override fun containsAll(elements: Collection<E>): Boolean = backing.containsAll(elements)
    override fun iterator(): MutableIterator<E> = backing.iterator()
    override fun add(element: E): Boolean = backing.add(element)
    override fun remove(element: E): Boolean = backing.remove(element)
    override fun clear() { backing.clear() }

    fun addAllTo(elements: Collection<E>) = super.addAll(elements)
    fun retainFrom(elements: Collection<E>) = super.retainAll(elements)
    fun removeFrom(elements: Collection<E>) = super.removeAll(elements)
}

fun main() {
    val set = BuilderSet<String>()
    println(set.add("x"))
    println(set.addAllTo(listOf("y", "z")))
    println(set.retainFrom(listOf("y")))
    println(set.removeFrom(listOf("y")))
    println(set.size)
}
