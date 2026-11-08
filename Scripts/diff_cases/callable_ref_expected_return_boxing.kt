data class Item(val group: Int, val score: Int)

fun scoreOf(item: Item): Int = item.score

// callable_ref_expected_return_boxing: a callable reference keeps its own function type, but an expected
// function type can demand a boxed return ABI. `(Item) -> Int` used as
// `(Item) -> Comparable<*>?` must box the primitive result, or the erased
// invoke result fails the `as Comparable` check inside `compareValues`.
fun main() {
    val byScore: (Item) -> Comparable<*>? = ::scoreOf
    println(byScore(Item(1, 2)))
    println(compareValues(byScore(Item(1, 2)), byScore(Item(2, 1))))
    val cmp = compareBy<Item>({ it.group }, { 0 }, { 0 }, ::scoreOf)
    println(listOf(Item(2, 1), Item(1, 2), Item(1, 1)).sortedWith(cmp).map { "${it.group}:${it.score}" })
}
