// KUU-1209: returned Comparator SAMs must preserve selector environments and data class arguments.
data class P(val g: Int, val s: Int)

fun group(p: P): Int = p.g
fun score(p: P): Int = p.s

fun capturedComparator(direction: Int): Comparator<P> {
    val first: (P) -> Int = { it.g * direction }
    val second: (P) -> Int = { it.s * direction }
    return compareBy<P>(first, second)
}

fun main() {
    val comparator = compareBy<P>({ it.g }, { it.s })
    println(comparator.compare(P(2, 1), P(1, 2)))
    println(comparator.compare(P(1, 2), P(2, 1)))
    println(comparator.compare(P(1, 2), P(1, 1)))
    println(comparator.compare(P(1, 1), P(1, 2)))
    println(comparator.compare(P(1, 2), P(1, 2)))

    var firstCalls = 0
    var secondCalls = 0
    val first: (P) -> Int = { firstCalls++; it.g }
    val second: (P) -> Int = { secondCalls++; it.s }
    val counted = compareBy<P>(first, second)
    println(counted.compare(P(2, 1), P(1, 2)))
    println("$firstCalls:$secondCalls")
    println(counted.compare(P(1, 2), P(1, 1)))
    println("$firstCalls:$secondCalls")

    val captured = capturedComparator(-1)
    println(captured.compare(P(2, 1), P(1, 2)))
    println(captured.compare(P(1, 2), P(1, 1)))
    println(captured.compare(P(1, 2), P(1, 2)))

    val references = compareBy<P>(::group, ::score)
    println(references.compare(P(2, 1), P(1, 2)))
    println(references.compare(P(1, 1), P(1, 2)))

    val three = compareBy<P>({ it.g }, { 0 }, { it.s })
    println(three.compare(P(2, 1), P(1, 2)))
    println(three.compare(P(1, 2), P(1, 1)))
    println(three.compare(P(1, 2), P(1, 2)))

    val four = compareBy<P>({ it.g }, { 0 }, { 0 }, ::score)
    println(four.compare(P(2, 1), P(1, 2)))
    println(four.compare(P(1, 1), P(1, 2)))
    println(four.compare(P(1, 2), P(1, 2)))

    val values = listOf(P(2, 1), P(1, 2), P(1, 1), P(1, 2))
    println(values.sortedWith(comparator).map { "${it.g}:${it.s}" })
    println(values.sortedWith(captured).map { "${it.g}:${it.s}" })
    println(values.sortedWith(three).map { "${it.g}:${it.s}" })
    println(values.sortedWith(four).map { "${it.g}:${it.s}" })

    // Adjacent single-selector regression reported as KUU-1199.
    println(compareBy<String> { it.length }.compare("a", "bbb"))
    println(compareByDescending<String> { it.length }.compare("a", "bbb"))
    println(arrayOf("bbb", "a", "cc").sortedArrayWith(compareBy<String> { it.length }).joinToString(","))
}
