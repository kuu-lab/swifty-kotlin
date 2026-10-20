fun main() {
    val distinct = sequenceOf(1, 1, 2, 3).distinct()
    println(distinct.toList()); println(distinct.toList())
    val a = distinct.iterator(); val b = distinct.iterator()
    println(a.next()); println(b.next()); println(a.next()); println(b.next())
    val by = sequenceOf(1, 3, 2, 4).distinctBy { it % 2 }
    println(by.toList()); println(by.toList())
    println(listOf(1, 2, 3, 4).windowed(3, 2, true))
    println(listOf(1, 2, 3, 4).chunked(3))
    println(listOf(1, 2, 3).sortedBy { -it })
    println("a::b:".split(":")); println("ab".split(""))
    println("\n  first\n    second\n".trimIndent())
    println("\n  |first\n  |second\n".trimMargin())
}
