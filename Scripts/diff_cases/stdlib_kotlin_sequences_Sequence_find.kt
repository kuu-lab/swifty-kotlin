fun main() {
    var firstCount = 0
    val first = sequenceOf(1, 2, 3, 4).find {
        firstCount += 1
        it == 2
    }
    println(first)
    println(firstCount)

    var lastCount = 0
    var lastValue = 0
    val last = sequenceOf(1, 2, 3, 2).findLast {
        lastCount += 1
        lastValue = it
        it == 2
    }
    println(last)
    println(lastCount)
    println(lastValue)

    println(emptySequence<Int>().find { true } == null)
    println(sequenceOf(1, 3).find { it % 2 == 0 } == null)
    println(sequenceOf<Int?>(null, 1).find { it != null })
    println(generateSequence(1) { it + 1 }.find { it == 3 })

    try {
        sequenceOf(1, 2, 3).find {
            if (it == 1) throw IllegalStateException("find predicate")
            false
        }
        println("find returned")
    } catch (_: IllegalStateException) {
        println("find threw")
    }

    try {
        sequenceOf(1, 2, 3).findLast {
            if (it == 1) throw IllegalStateException("findLast is forward")
            it == 3
        }
        println("findLast returned")
    } catch (_: IllegalStateException) {
        println("findLast threw")
    }
}
