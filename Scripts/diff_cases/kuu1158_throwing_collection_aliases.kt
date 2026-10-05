class ThrowingList : AbstractMutableList<Int>() {
    override val size: Int get() = 0
    override fun get(index: Int): Int = throw IllegalStateException("get")
    override fun set(index: Int, element: Int): Int = throw IllegalStateException("set")
    override fun add(index: Int, element: Int) { throw IllegalStateException("addAt") }
    override fun removeAt(index: Int): Int = throw IllegalStateException("removeAt")
    override fun add(element: Int): Boolean = throw IllegalStateException("add")
    override fun addAll(elements: Collection<Int>): Boolean = throw IllegalStateException("addAll")
    override fun remove(element: Int): Boolean = throw IllegalStateException("remove")
    override fun clear() { throw IllegalStateException("clear") }
    override fun removeAll(elements: Collection<Int>): Boolean = throw IllegalStateException("removeAll")
    override fun retainAll(elements: Collection<Int>): Boolean = throw IllegalStateException("retainAll")
}

fun mutateCollection(target: MutableCollection<Int>, path: Int) {
    when (path) {
        0 -> target.add(1)
        1 -> target.addAll(emptyList<Int>())
        2 -> target.remove(1)
        3 -> target.clear()
        4 -> target.removeAll(emptyList<Int>())
        5 -> target.retainAll(emptyList<Int>())
    }
}

fun mutateList(target: MutableList<Int>, path: Int) {
    when (path) {
        0 -> target.add(1)
        1 -> target.addAll(emptyList<Int>())
        2 -> target.remove(1)
        3 -> target.clear()
        4 -> target.removeAll(emptyList<Int>())
        5 -> target.retainAll(emptyList<Int>())
    }
}

fun main() {
    for (path in 0..5) {
        try {
            mutateCollection(ThrowingList(), path)
            println("accepted")
        } catch (e: UnsupportedOperationException) {
            println("wrong exception")
        } catch (e: IllegalStateException) {
            println(e.message)
        }
    }
    for (path in 0..5) {
        try {
            mutateList(ThrowingList(), path)
            println("accepted")
        } catch (e: UnsupportedOperationException) {
            println("wrong exception")
        } catch (e: IllegalStateException) {
            println(e.message)
        }
    }
}
