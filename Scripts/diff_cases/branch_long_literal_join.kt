fun f(endIndex: Long): Long = endIndex
fun g(x: Long): Long {
    val e = when (x) { -1L -> 5L; 0L -> 101; else -> x - 1 }
    return f(endIndex = e)
}
fun h(x: Long): Long {
    val e = if (x > 0) x else 102
    return f(e)
}
fun reversed(x: Long): Long {
    val e = if (x > 0) -103 else x
    return f(e)
}
fun blocks(x: Long): Long {
    val e = when { x > 0 -> { val unused = 1; +104 }; else -> x }
    return f(e)
}
fun nested(x: Long, flag: Boolean): Long {
    val e = if (flag) { if (flag) 105 else 106 } else x
    return f(e)
}
fun nullable(x: Long?, flag: Boolean): Long? {
    val e = if (flag) x else 107
    return e
}
fun main() {
    println(g(-1L))
    println(g(0L))
    println(g(8L))
    println(h(9L))
    println(h(0L))
    println(reversed(9L))
    println(reversed(0L))
    println(blocks(9L))
    println(blocks(0L))
    println(nested(9L, true))
    println(nested(9L, false))
    println(nullable(null, true))
    println(nullable(null, false))
}
