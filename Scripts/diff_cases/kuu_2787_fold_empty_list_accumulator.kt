// KUU-2787 regression: with an expected type, an uninferred initial value
// (`emptyList()`) must widen to the lambda's result type instead of pinning the
// accumulator to `List<Nothing>`. (Without an expected type kotlinc itself
// rejects these calls, so only the typed forms appear here.)
fun openDoors(doors: List<Boolean>): List<Int> =
    doors.foldIndexed(emptyList()) { i, acc, door -> if (door) acc + (i + 1) else acc }

fun lengthsOf(words: List<String>): List<Int> =
    words.fold(emptyList()) { acc, w -> acc + w.length }

fun main() {
    val r2: List<Int> = listOf(1, 2, 3).fold(emptyList()) { acc, x -> acc + x }
    println(r2)

    val r3 = listOf(1, 2, 3).fold(emptyList<Int>()) { acc, x -> acc + x }
    println(r3)

    println(openDoors(listOf(true, false, true)))
    println(lengthsOf(listOf("a", "bb", "c")))
    println(lengthsOf(listOf("a", "bb", "c")).sum())

    val rightFolded: List<Int> = listOf(1, 2, 3).foldRight(emptyList()) { x, acc -> acc + x }
    println(rightFolded)

    val seqFolded: List<Int> = sequenceOf(4, 5).fold(emptyList()) { acc, x -> acc + x }
    println(seqFolded)

    val grouped: Map<Int, List<String>> = listOf("a", "bb", "cc").fold(emptyMap()) { acc, w ->
        acc + (w.length to (acc[w.length].orEmpty() + w))
    }
    println(grouped)
}
