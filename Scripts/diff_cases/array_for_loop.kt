fun sumInts(values: IntArray): Int {
    var total = 0
    for (v in values) {
        total += v
    }
    return total
}

fun <T> firstOrNullOf(items: Array<T>): T? {
    for (item in items) {
        return item
    }
    return null
}

fun main() {
    for (b in "HI".encodeToByteArray()) {
        println(b)
    }
    for (x in intArrayOf(10, 20, 30)) {
        println(x)
    }
    for (s in arrayOf("a", "b", "c")) {
        println(s)
    }
    for (x in IntArray(4) { it * it }) {
        println(x)
    }
    for (x in longArrayOf(100L, 200L)) {
        println(x)
    }
    for (x in doubleArrayOf(1.5, 2.5)) {
        println(x)
    }
    for (x in floatArrayOf(1.5f, 2.5f)) {
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
    for (inner in arrayOf(intArrayOf(1, 2), intArrayOf(3))) {
        for (v in inner) {
            println(v)
        }
    }
    println(sumInts(intArrayOf(1, 2, 3, 4)))
    println(firstOrNullOf(arrayOf("p", "q")))
    for (x in IntArray(0)) {
        println(x)
    }
    println("empty done")
    for (x in intArrayOf(1, 2, 3, 4, 5)) {
        if (x == 2) continue
        if (x == 4) break
        println(x)
    }
}
