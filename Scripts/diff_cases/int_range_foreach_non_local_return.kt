// KUU-3993: range/progression forEach must allow returns from the enclosing function.
fun rangeBareReturn() {
    (1..3).forEach {
        println("range:$it")
        if (it == 2) return
    }
    println("range:after")
}

fun listBareReturn() {
    listOf(1).forEach {
        println("list:$it")
        if (it == 1) return
    }
    println("list:after")
}

fun rangeValueReturn(range: IntRange): Int {
    range.forEach { if (it == 2) return it }
    return -1
}

fun progressionValueReturn(progression: IntProgression): Int {
    var visited = 0
    progression.forEach {
        visited++
        if (visited == 2) return it
    }
    return -1
}

fun nestedReturn(): Int {
    (1..3).forEach { outer ->
        (3 downTo 1 step 2).forEach { inner ->
            if (outer == 2 && inner == 1) return outer * 10 + inner
        }
    }
    return -1
}

fun labeledReturn(): Int {
    var sum = 0
    (1..3).forEach {
        if (it == 2) return@forEach
        sum += it
    }
    return sum
}

fun returnWithFinally(): Int {
    try {
        (1..3).forEach { if (it == 2) return it }
    } finally {
        println("finally")
    }
    return -1
}

fun main() {
    rangeBareReturn()
    listBareReturn()
    println(rangeValueReturn(1..3))
    println(rangeValueReturn(3..1))
    println(progressionValueReturn(1..5 step 2))
    println(progressionValueReturn(5 downTo 1 step 2))
    println(progressionValueReturn(3..1 step 2))
    println(nestedReturn())
    println(labeledReturn())
    println(returnWithFinally())
}
