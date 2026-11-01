class Counter(var v: Int) {
    operator fun plusAssign(x: Int) { v += x }
}

fun main() {
    val l = mutableListOf(1)
    l.apply { this += 2 }
    println(l)

    val m = mutableListOf(10, 20, 30)
    m.apply { this -= 20 }
    println(m)

    val c = Counter(1)
    c.apply { this += 5 }
    println(c.v)
    c.run { this += 1 }
    println(c.v)
    c.apply { this@apply += 3 }
    println(c.v)
}
