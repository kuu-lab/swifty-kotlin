// KUU-2006: Preserve multiple components, skipped entries, and parameter positions.
class SingleBox(val value: Int) {
    operator fun component1(): Int = value
}

fun main() {
    val double: (List<Int>) -> Int = { (a, b) -> a + b }
    println(double(listOf(7, 8)))
    val custom: (SingleBox) -> Int = { (a) -> a }
    println(custom(SingleBox(7)))
    val ignored: (List<Int>) -> Int = { (_) -> 7 }
    println(ignored(listOf(7, 8)))
    val mixed: (Int, List<Int>) -> Int = { acc, (a) -> acc + a }
    println(mixed(1, listOf(7, 8)))
    val reversed: (List<Int>, Int) -> Int = { (a), acc -> a + acc }
    println(reversed(listOf(7, 8), 1))
    val annotated = { (a): List<Int> -> a }
    println(annotated(listOf(7, 8)))
    val annotatedMixed = { acc: Int, (a): List<Int> -> acc + a }
    println(annotatedMixed(1, listOf(7, 8)))
}
