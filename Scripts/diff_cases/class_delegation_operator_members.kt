// KUU-3260: delegated interface members keep their operator/infix modifiers

interface Indexed {
    operator fun get(i: Int): Int
    operator fun contains(x: Int): Boolean
    infix fun combine(other: Int): Int
}

class Impl : Indexed {
    override fun get(i: Int) = i * 2
    override fun contains(x: Int) = x > 0
    override infix fun combine(other: Int) = other + 7
}

class Box(val d: Indexed) : Indexed by d

fun main() {
    val b = Box(Impl())
    println(b[3])
    println(4 in b)
    println(-1 in b)
    println(b combine 5)
}
