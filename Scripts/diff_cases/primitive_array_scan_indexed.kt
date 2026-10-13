private fun findEmptySpace(counts: Set<Int>): IntArray =
    IntArray(counts.max() + 1)
        .scanIndexed(if (0 in counts) 0 else 1) { index, acc, _ ->
            acc + if (index !in counts) 1 else 0
        }
        .toIntArray()

fun main() {
    println(intArrayOf(0,0,0).scanIndexed(1){index,acc,_-> acc+index}.joinToString())

    println(findEmptySpace(setOf(0, 2)).joinToString())
    println(findEmptySpace(setOf(1, 2)).joinToString())

    val empty = intArrayOf().scanIndexed(7) { index, acc, value -> acc + index + value }
    println(empty.joinToString())

    val strings = intArrayOf(4, -1, 3).scanIndexed("seed") { index, acc, value ->
        "$acc|$index:$value"
    }
    println(strings.joinToString(";"))
}
