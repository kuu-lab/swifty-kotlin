fun main() {
    val missing: Sequence<Int>? = null
    val present: Sequence<Int>? = sequenceOf(1, 2)
    println(missing.orEmpty().toList())
    println(present.orEmpty().toList())

    val iterator = sequenceOf(3, 4).iterator()
    println(iterator.next())
}
