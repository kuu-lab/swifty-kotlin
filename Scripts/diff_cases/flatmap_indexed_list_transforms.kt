// KUU-4063: List.flatMapIndexed committed to the List specialization without
// retrying the Iterable.flatMapIndexed variants for non-List transform
// results (KSWIFTK-TYPE-0001).
fun main() {
    println(listOf(1, 2, 3).flatMapIndexed { i, v -> sequenceOf(i, v) })
    println(listOf(1, 2, 3).flatMapIndexed { i, v -> i..v })
    println(listOf(1, 2).flatMapIndexed { i, v -> listOf(i, v) })
    val ml: MutableList<Int> = mutableListOf(1, 2)
    println(ml.flatMapIndexed { i, v -> sequenceOf(i, v) })
}
