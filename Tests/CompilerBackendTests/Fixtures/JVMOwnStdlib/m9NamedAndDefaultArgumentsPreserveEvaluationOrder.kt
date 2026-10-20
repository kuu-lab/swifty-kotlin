fun mark(n: Int): Int { println(n); return n }
fun combine(a: Int = mark(1), b: Int = a + mark(2), c: Int = mark(3)): Int = a * 100 + b * 10 + c
fun Int.decorate(left: Int = this, right: Int = 2): Int = this + left + right
class Box(val a: Int = mark(4), val b: Int = a + mark(5)) {
    constructor(text: String, n: Int = 5): this(b = n, a = 0)
    fun result(offset: Int = a): Int = a + b + offset
}
fun main() {
    println(combine(c = mark(9), a = mark(7)))
    println(combine())
    println(2.decorate(right = 4))
    println(Box(b = mark(6)).result())
    println(Box("hello").result(offset = 2))
    println(Box().result())
}
