fun testIfElse() {
    var n = 0
    if (1 < 0) n = 5 else @Suppress("X") n = 7
    println(n)
    if (1 > 0) @Suppress("X") n = 9 else n = 2
    println(n)
    if (1 > 0) @Suppress("X") n += 10 else n += 20
    println(n)
    if (1 < 0) n += 100 else @Suppress("X") n += 200
    println(n)
}

fun f(list: List<Any>): Int {
    fun walk(l: List<Any>): Int {
        var n = 0
        for (e in l) {
            if (e !is List<*>) n++
            else @Suppress("UNCHECKED_CAST") n += (e as List<Any>).size
        }
        return n
    }
    return walk(list)
}

fun main() {
    testIfElse()
    println(f(listOf(listOf(1, 2) as Any, 3)))
}
