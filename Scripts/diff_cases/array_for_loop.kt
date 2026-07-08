fun sumInts(values: IntArray): Int {
    var total = 0
    for (v in values) {
        total += v
    }
    return total
}

fun main() {
    for (x in arrayOf(10, 20, 30)) {
        println(x)
    }

    val strings = arrayOf("a", "b", "c")
    for (x in strings) {
        println(x)
    }

    for (x in intArrayOf(1, 2, 3)) {
        println(x)
    }

    val ints = intArrayOf(4, 5, 6)
    for (x in ints) {
        println(x)
    }

    val squares = IntArray(4) { it * it }
    for (x in squares) {
        println(x)
    }

    for (x in byteArrayOf(1, 2, 3)) {
        println(x)
    }

    for (x in longArrayOf(100L, 200L)) {
        println(x)
    }

    for (x in doubleArrayOf(1.5, 2.5)) {
        println(x)
    }

    for (x in booleanArrayOf(true, false)) {
        println(x)
    }

    for (x in charArrayOf('x', 'y')) {
        println(x)
    }

    for (x in shortArrayOf(7, 8)) {
        println(x)
    }

    for (x in intArrayOf()) {
        println("should not print: $x")
    }
    println("empty-ok")

    println(sumInts(intArrayOf(1, 2, 3, 4)))
}
