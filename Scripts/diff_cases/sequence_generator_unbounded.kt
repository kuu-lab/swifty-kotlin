fun main() {
    for (size in listOf(99999, 100000, 100001, 150000)) {
        println(generateSequence(0) { it + 1 }.take(size).last())
    }

    val finite = generateSequence(0) { if (it < 149999) it + 1 else null }
    println(finite.count())
    println(finite.last())
    val materialized = finite.toList()
    println(materialized.size)
    println(materialized.last())

    var calls = 0
    println(generateSequence(0) { calls++; it + 1 }.take(150000).last())
    println(calls)
    println(generateSequence(0) { it + 1 }.filter { it >= 150000 }.first())
    println(generateSequence(0) { it + 1 }.first { it > 100000 })
    println(generateSequence(0) { it + 1 }.firstOrNull())
    println(generateSequence(0) { it + 1 }.firstOrNull { it > 100000 })
    println(generateSequence(0) { it + 1 }.drop(150000).take(1).last())

    var next = 0
    println(generateSequence {
        val value = next
        next += 1
        value
    }.take(150000).last())
    println(next)
    next = 0
    val nullableList = generateSequence {
        if (next < 150000) {
            val value = next
            next += 1
            value
        } else null
    }.toList()
    println(nullableList.size)
    println(nullableList.last())

    val iterator = generateSequence(0) { if (it < 149999) it + 1 else null }.iterator()
    var seen = 0
    var last = -1
    while (iterator.hasNext()) {
        last = iterator.next()
        seen++
    }
    println(seen)
    println(last)

    next = 0
    val nullableIterator = generateSequence {
        if (next < 150000) {
            val value = next
            next += 1
            value
        } else null
    }.iterator()
    seen = 0
    while (nullableIterator.hasNext()) {
        last = nullableIterator.next()
        seen++
    }
    println(seen)
    println(last)

    println(sequence {
        var value = 0
        while (true) yield(value++)
    }.take(150000).last())
    println(sequence {
        for (value in 0 until 150000) yield(value)
    }.count())

    try {
        generateSequence(0) {
            if (it == 100000) throw IllegalStateException("past former limit")
            it + 1
        }.take(150000).toList()
    } catch (e: IllegalStateException) {
        println(e.message)
    }
}
