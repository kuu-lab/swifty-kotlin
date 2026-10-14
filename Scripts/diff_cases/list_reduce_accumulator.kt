// KUU-2065: List.reduce must retain S independently from T : S.
open class ReduceBase(val total: Int)
class ReduceLeaf(total: Int) : ReduceBase(total)

fun ReduceBase.combine(other: ReduceBase): ReduceBase = ReduceBase(total + other.total)

fun userExtension(): String {
    fun List<Int>.reduce(): String = "user"
    return listOf(1).reduce()
}

fun inferred(values: List<ReduceLeaf>): ReduceBase =
    values.reduce<ReduceBase, ReduceLeaf> { acc, item -> item.combine(acc) }

fun explicit(values: List<ReduceLeaf>): ReduceBase =
    values.reduce<ReduceBase, ReduceLeaf> { acc: ReduceBase, item: ReduceLeaf -> item.combine(acc) }

fun iterable(values: Iterable<ReduceLeaf>): ReduceBase =
    values.reduce<ReduceBase, ReduceLeaf> { acc, item -> item.combine(acc) }

fun earlyReturn(values: List<Int>): Int {
    values.reduce { acc, item -> if (item == 2) return 42 else acc + item }
    return -1
}

fun main() {
    val values = listOf(ReduceLeaf(1), ReduceLeaf(2), ReduceLeaf(3))
    println(inferred(values).total)
    println(explicit(values).total)
    println(iterable(values).total)
    println(values.reduce<ReduceBase, ReduceLeaf>(operation = { acc, item -> item.combine(acc) }).total)
    val operation: (ReduceBase, ReduceLeaf) -> ReduceBase = { acc, item -> item.combine(acc) }
    println(values.reduce(operation).total)
    println(values.reduce<ReduceLeaf, ReduceLeaf> { _, item -> item }.total)
    println(inferred(listOf(ReduceLeaf(7))).total)
    println(listOf(1, 2, 3).reduce { acc, item -> acc + item })
    println(userExtension())
    println(earlyReturn(listOf(1, 2, 3)))
    try {
        inferred(emptyList<ReduceLeaf>())
    } catch (error: UnsupportedOperationException) {
        println(error.message)
    }
}
