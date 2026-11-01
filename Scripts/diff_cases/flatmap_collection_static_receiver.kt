// KUU-4063: a statically Collection-typed receiver left flatMap's callee
// unbound and the call failed at link time with an undefined `_flatMap`.
fun flattenAll(c: Collection<Int>): List<Int> {
    return c.flatMap { 1..it }
}
fun main() {
    val c: Collection<Int> = listOf(1, 2, 3)
    println(c.flatMap { 1..it })
    println(c.flatMap { listOf(it) })
    println(c.flatMap { sequenceOf(it) })
    println(flattenAll(c))
    val mc: MutableCollection<Int> = mutableListOf(2, 3)
    println(mc.flatMap { sequenceOf(it) })
}
