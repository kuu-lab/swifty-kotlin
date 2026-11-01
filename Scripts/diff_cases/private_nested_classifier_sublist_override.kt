// KUU-3927: kotlinx.collections.immutable's ImmutableList.SubList shape —
// a private nested class inside an interface extends AbstractList (which
// has its own private `SubList`) and overrides the real `List.subList`
// while calling its own constructor. The unqualified `SubList` reference
// must resolve to the class itself, not the supertype's private nested
// classifier (KSWIFTK-SEMA-0040 before the KUU-3798 fix).
interface ImmutableList<out E> : List<E> {
    override fun subList(fromIndex: Int, toIndex: Int): ImmutableList<E> =
        SubList(this, fromIndex, toIndex)

    private class SubList<E>(
        private val source: ImmutableList<E>,
        private val fromIndex: Int,
        private val toIndex: Int
    ) : ImmutableList<E>, AbstractList<E>() {
        private var _size: Int = toIndex - fromIndex

        override fun get(index: Int): E {
            if (index < 0 || index >= _size) throw IndexOutOfBoundsException("index $index")
            return source[fromIndex + index]
        }

        override val size: Int get() = _size

        override fun subList(fromIndex: Int, toIndex: Int): ImmutableList<E> =
            SubList(source, this.fromIndex + fromIndex, this.fromIndex + toIndex)
    }
}

class MyList<E>(private val items: List<E>) : ImmutableList<E>, AbstractList<E>() {
    override val size: Int get() = items.size
    override fun get(index: Int): E = items[index]
    // kotlinc requires an explicit override: MyList inherits both
    // ImmutableList's default and AbstractList's implementation.
    override fun subList(fromIndex: Int, toIndex: Int): ImmutableList<E> =
        MyList(items.subList(fromIndex, toIndex))
}

fun main() {
    val list: ImmutableList<String> = MyList(listOf("a", "b", "c", "d"))
    val sub = list.subList(1, 3)
    println(sub.size)
    println(sub[0])
    println(sub[1])
    // SubList.subList override calls its own constructor (line that failed
    // upstream at ImmutableList.kt:54).
    val subsub = sub.subList(0, 1)
    println(subsub.size)
    println(subsub[0])
}
