package golden.sema

@Suppress("DEPRECATION_ERROR")
fun main() {
    val mutable: MutableList<Int> = mutableListOf(1, 2, 3)
    val mutableReversed: MutableList<Int> = mutable.asReversed()
    val readOnly: List<Int> = mutable
    val readOnlyReversed: List<Int> = readOnly.asReversed()
    val indexed: Int = mutable.remove(index = 0)
    val element: Boolean = mutable.remove(2)
    val first: Int = mutable.removeFirst()
    val firstOrNull: Int? = mutable.removeFirstOrNull()
    val last: Int = mutable.removeLast()
    val lastOrNull: Int? = mutable.removeLastOrNull()
    val removePredicate: Boolean = mutable.removeAll { it > 0 }
    val retainPredicate: Boolean = mutable.retainAll { it > 0 }
    val reversed: Unit = mutable.reverse()
    val shuffled: Unit = mutable.shuffle()
    val shuffledSeeded: Unit = mutable.shuffle(kotlin.random.Random(1))
    println(mutableReversed)
    println(readOnlyReversed)
    println(indexed)
    println(element)
    println(first)
    println(firstOrNull)
    println(last)
    println(lastOrNull)
    println(removePredicate)
    println(retainPredicate)
    println(reversed)
    println(shuffled)
    println(shuffledSeeded)
}
