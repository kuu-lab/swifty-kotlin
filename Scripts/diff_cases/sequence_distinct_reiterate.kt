fun main() {
    val distinct = sequenceOf(1, 2, 1, 3, 2).distinct()
    println(distinct.toList())
    println(distinct.toList())

    val byLength = sequenceOf("a", "bb", "c", "dd", "eee").distinctBy { it.length }
    println(byLength.toList())
    println(byLength.toList())

    val withNull = sequenceOf<String?>(null, "x", null, "x", "y").distinct()
    println(withNull.toList())
    println(withNull.count())

    val outer = distinct.iterator()
    val inner = distinct.iterator()
    println("${outer.next()} ${inner.next()} ${outer.next()} ${inner.next()}")
}
