abstract class BaseList<E> : MutableList<E> {
    override fun add(element: E): Boolean {
        println("BaseList.add")
        return true
    }
    override fun remove(element: E): Boolean {
        println("BaseList.remove")
        return true
    }
    override fun removeAll(elements: Collection<E>): Boolean {
        println("BaseList.removeAll")
        return true
    }
    override fun retainAll(elements: Collection<E>): Boolean {
        println("BaseList.retainAll")
        return true
    }
}

class BuilderList<E> : BaseList<E>(), MutableList<E> {
    private val backing = mutableListOf<E>()
    override val size: Int get() = backing.size
    override fun isEmpty(): Boolean = backing.isEmpty()
    override fun contains(element: E): Boolean = backing.contains(element)
    override fun containsAll(elements: Collection<E>): Boolean = backing.containsAll(elements)
    override fun iterator(): MutableIterator<E> = backing.iterator()
    override fun get(index: Int): E = backing.get(index)
    override fun set(index: Int, element: E): E = backing.set(index, element)
    override fun indexOf(element: E): Int = backing.indexOf(element)
    override fun lastIndexOf(element: E): Int = backing.lastIndexOf(element)
    override fun listIterator(): MutableListIterator<E> = backing.listIterator()
    override fun listIterator(index: Int): MutableListIterator<E> = backing.listIterator(index)
    override fun subList(fromIndex: Int, toIndex: Int): MutableList<E> = backing.subList(fromIndex, toIndex)
    override fun add(index: Int, element: E) {
        backing.add(index, element)
    }
    override fun addAll(elements: Collection<E>): Boolean = backing.addAll(elements)
    override fun addAll(index: Int, elements: Collection<E>): Boolean = backing.addAll(index, elements)
    override fun clear() {
        backing.clear()
    }
    override fun removeAt(index: Int): E = backing.removeAt(index)

    fun addTo(element: E) = super.add(element)
    fun removeFrom(element: E) = super.remove(element)
    fun removeAllFrom(elements: Collection<E>) = super.removeAll(elements)
    fun retainFrom(elements: Collection<E>) = super.retainAll(elements)
}

fun main() {
    val list = BuilderList<String>()
    println(list.addTo("x"))
    println(list.removeFrom("x"))
    println(list.removeAllFrom(listOf("y", "z")))
    println(list.retainFrom(listOf("y")))
    println(list.size)
}
