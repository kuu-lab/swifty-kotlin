fun main() {
    val fromIterator = Sequence { listOf(1, 2, 3).iterator() }
    println(fromIterator.toList())
    println(fromIterator.toList())

    println(sequenceOf<Int>().toList())
    println(sequenceOf(42).toList())
    println(sequenceOf("single").toList())

    println(generateSequence(1) { if (it < 8) it * 2 else null }.toList())
    println(generateSequence({ 10 }) { if (it > 1) it / 2 else null }.toList())
    val next: () -> Int? = { 7 }
    println(generateSequence(next).take(3).toList())

    val built = sequence {
        yield(1)
        yieldAll(listOf(2, 3))
        yieldAll(sequenceOf(4))
    }
    println(built.toList())

    val iter = iterator {
        yield(10)
        yield(20)
    }
    val values = mutableListOf<Int>()
    for (value in iter) values.add(value)
    println(values)
}
