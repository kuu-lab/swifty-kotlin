interface Box<T> { val value: T }
class BoxImpl<T>(override val value: T) : Box<T>

fun <T, R> Iterable<Box<T>>.zip(transform: (List<T>) -> R): Box<R> =
    BoxImpl(transform(map { it.value }))

fun main() {
    val boxes: List<Box<Int>> = listOf(BoxImpl(1), BoxImpl(2))

    // A function-typed argument cannot match the bundled zip(other: Iterable<R>)
    // overloads, so the user extension must be selected.
    val zipped: Box<String> = boxes.zip { list -> "sum=${list.sum()}" }
    println(zipped.value)

    // The same selection must apply through a chained map(...) receiver.
    val viaMap: Box<String> = boxes.map { it }.zip { list -> "mapped=${list.size}" }
    println(viaMap.value)

    // Collection-typed arguments still reach the stdlib zip overloads.
    println(listOf(1, 2).zip(listOf("x", "y")))
    println(listOf(1, 2).zip(listOf("x", "y")) { l, r -> "$l$r" })
}
