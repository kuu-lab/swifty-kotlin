package kotlin.collections

// KSP-944: source-backed MutableList nominal declaration and initializer
// factory. Mutation members remain compiler/runtime residuals until their
// dedicated migration tasks land.
public interface MutableList<E> : List<E>, MutableCollection<E>

/**
 * Creates a mutable list whose elements are produced in ascending index order.
 */
public inline fun <T> MutableList(size: Int, init: (index: Int) -> T): MutableList<T> {
    if (size < 0) throw IllegalArgumentException("Illegal Capacity: $size")

    val list = mutableListOf<T>()
    var index = 0
    while (index < size) {
        list.add(init(index))
        index++
    }
    return list
}
