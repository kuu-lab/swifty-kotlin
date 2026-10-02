// Labels derived from the callee name (`this@with`, `this@run`, `this@buildString`)
// must resolve to the matching lambda receiver, including nested cases where the
// innermost receiver differs from the labelled one.
fun main() {
    val lst = listOf(1, 2, 3)
    println(with(lst) { buildList<Int> { for (e in this@with) add(e * 2) } })
    println("ab".run { buildString { append(this@run); append(length) } })
    println(buildString { append("xy"); append(this@buildString.length) })
    println("q".let { s -> buildString { append(s); append(this@buildString.length) } })
    sameTypeNesting()
}

fun sameTypeNesting() {
    // Inner receiver has the same type as the outer one: each label and the bare
    // `this` must still name their own receiver.
    "a".run { "b".apply { println(this@run + "," + this@apply + "," + this) } }
    with(listOf(1, 2)) { with(listOf(9)) { println(size); println(this@with.size) } }
}
