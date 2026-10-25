// DIFF_JVM: KUU-2851 covers List/Iterable single and elementAt extension declarations.
fun main() {
    val values = listOf(1, 2, 3)
    println(values.singleOrNull())
    println(values.singleOrNull { it == 2 })
    println(values.singleOrNull { it > 0 })
    println(listOf(2).single())
    println(values.single { it == 2 })
    println(values.elementAtOrNull(5))
    println(values.elementAtOrElse(5) { it })
    println(values.elementAt(1))
    val iterable: Iterable<Int> = values
    println(iterable.singleOrNull())
    println(iterable.elementAtOrNull(1))
    val singleton: Iterable<Int> = listOf(2)
    println(singleton.single())
}
