// KSP-700: core collection / iterable / Comparable / List interface shells are
// Kotlin source-backed. This case exercises the source-declared members on
// List-typed receivers (get / isEmpty / listIterator overloads) and an
// AbstractList subclass that relies on the source-backed default iterator and
// listIterator implementations.

class FixedList(private val base: Int) : AbstractList<Int>() {
    override val size: Int
        get() = 3

    override fun get(index: Int): Int = base + index
}

fun main() {
    val list: List<Int> = listOf(10, 20, 30)
    println(list[1])
    println(list.isEmpty())

    val it = list.listIterator()
    println(it.hasNext())
    println(it.next())
    println(it.nextIndex())

    val itAt = list.listIterator(2)
    println(itAt.hasPrevious())
    println(itAt.previous())
    println(itAt.previousIndex())

    val mutableList: MutableList<Int> = mutableListOf(1, 2, 3)
    val mutableIterator = mutableList.listIterator()
    println(mutableIterator.next())
    val mutableIteratorAt = mutableList.listIterator(1)
    println(mutableIteratorAt.nextIndex())
    println(mutableIteratorAt.next())

    val fixed = FixedList(5)
    println(fixed[0])
    println(fixed.size)
    var sum = 0
    for (element in fixed) {
        sum += element
    }
    println(sum)

    val fixedIterator = fixed.listIterator(1)
    println(fixedIterator.previousIndex())
    println(fixedIterator.next())

    println(fixed.indexOf(6))
    println(fixed.lastIndexOf(7))
    val slice = fixed.subList(1, 3) as AbstractList<Int>
    println(slice.size)
    println(slice[0])
    println(fixed == FixedList(5))
    println(fixed.hashCode() == FixedList(5).hashCode())

    val collection: Collection<Int> = list
    println(collection.size)
    println(collection.contains(20))

    val comparable: Comparable<Int> = 7
    println(comparable.compareTo(9) < 0)
}
