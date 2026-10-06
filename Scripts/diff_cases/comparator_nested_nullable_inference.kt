data class P(val k: Int)

fun contextualComparator(): Comparator<P?> = nullsFirst(compareBy { it!!.k })

fun main() {
    val values = listOf<P?>(P(2), null, P(1), P(3))
    println(listOf<P?>(P(1), null).sortedWith(nullsFirst(compareBy { it!!.k })))
    println(values.sortedWith(nullsFirst(compareBy { it!!.k })))
    println(values.sortedWith(nullsLast(compareByDescending { it!!.k })))
    println(values.sortedWith(contextualComparator()))
    println(values.sortedWith(nullsFirst(compareBy<P?> { it!!.k })))
    println(values.sortedWith(nullsFirst(compareBy { p -> p!!.k })))
    println(values.sortedWith(nullsFirst(compareBy({ it!!.k }, { it!!.k }))))
    println(listOf(P(2), P(1)).sortedWith(compareBy { it.k }))
    println(values.sortedWith(compareBy { it?.k }))
}
