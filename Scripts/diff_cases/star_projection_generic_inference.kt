// KSP-651: star projections must still constrain type variables of generic calls
// (declaration-site variance projection must not swallow the `*` case).
fun <T> firstOrDef(xs: List<T>): T? = xs.firstOrNull()

fun <T> sizeOf(xs: Collection<T>): Int = xs.size

fun <T> countSeq(s: Sequence<T>): Int = s.count()

fun <T : Comparable<T>> maxOfList(xs: List<T>): T? = xs.maxOrNull()

fun useStarList(xs: List<*>): String {
    val first = firstOrDef(xs)
    val size = sizeOf(xs)
    return "$first $size"
}

fun useStarSequence(s: Sequence<*>): Int = countSeq(s)

fun main() {
    println(useStarList(listOf(7, 8)))
    println(useStarList(listOf("a")))
    println(useStarSequence(sequenceOf(1, 2, 3)))
    println(maxOfList(listOf(3, 9, 4)))
    println(sizeOf(setOf<Int>()))
}
