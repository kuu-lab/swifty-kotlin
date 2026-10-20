fun main() {
    val values = sequence { println("start"); yield(1); println("next"); yieldAll(listOf(2, 3)); yieldAll(sequenceOf(4)); yieldAll(listOf(5).iterator()); println("done") }
    println("created")
    val it = values.iterator(); println("iterator"); println(it.hasNext()); println(it.hasNext()); println(it.next()); println(it.next()); println(values.toList()); println(it.asSequence().toList())
    val empty = sequence<Int> { yieldAll(emptyList<Int>()); yieldAll(emptySequence<Int>()); yieldAll(emptyList<Int>().iterator()); println("empty"); yield(9) }
    println(empty.toList())
    val direct = iterator { yield("a"); yieldAll(sequenceOf("b", "c")) }
    println(direct.next()); println(direct.asSequence().joinToString()); println(direct.hasNext())
    try { direct.next() } catch (e: NoSuchElementException) { println("end") }
    println(sequence<Int> {}.toList())
    println(sequence<Int?>(block = { yield(null); yield(1); yieldAll(listOf(null, 2)) }).toList())
}
