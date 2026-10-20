import fixture.CaseInsensitiveSets
fun main() {
    val removed = CaseInsensitiveSets.fresh() as Set<String>
    val source = setOf("A", "B")
    val result: Set<String> = source - removed
    println(result); println(source)
    val iterable: Iterable<String> = listOf("A", "B", "A")
    println(iterable - removed)
    println(source - listOf("a")); println(iterable - listOf("a"))
    println(source - arrayOf("a")); println(iterable - arrayOf("a"))
    println(source - sequenceOf("a")); println(iterable - sequenceOf("a"))
}
