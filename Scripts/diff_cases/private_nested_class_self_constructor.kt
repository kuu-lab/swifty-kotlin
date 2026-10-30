// KUU-3798: a private nested class must be able to invoke its own
// constructor from inside its own member functions. The supertype's own
// same-named private nested classifier (AbstractList.SubList) is not
// inherited and must not shadow the lexical declaration.
interface IL<out E> : List<E> {
    fun subL(a: Int, b: Int): IL<E> = SubList(this, a, b)

    private class SubList<E>(
        private val source: IL<E>,
        private val fromIndex: Int,
        private val toIndex: Int
    ) : IL<E>, AbstractList<E>() {
        override val size: Int get() = toIndex - fromIndex
        override fun get(index: Int): E {
            if (index < 0 || index >= size) throw IndexOutOfBoundsException("index $index")
            return source[fromIndex + index]
        }
        override fun subL(a: Int, b: Int): IL<E> = SubList(source, a, b)
    }
}

class BaseList<E>(private val items: List<E>) : IL<E>, AbstractList<E>() {
    override val size: Int get() = items.size
    override fun get(index: Int): E = items[index]
}

fun main() {
    val list: IL<String> = BaseList(listOf("a", "b", "c", "d"))
    val sub = list.subL(1, 3)
    println(sub.size)
    println(sub[0])
    println(sub[1])
    // Calls SubList.subL, which constructs SubList from inside SubList.
    val subsub = sub.subL(0, 1)
    println(subsub.size)
    println(subsub[0])
}
