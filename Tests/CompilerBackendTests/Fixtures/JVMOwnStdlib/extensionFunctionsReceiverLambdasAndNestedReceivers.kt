fun Int.twice(): Int = this * 2
fun Int.withOperation(block: Int.() -> Int): Int = block()
fun String?.orFallback(): String = if (this == null) "fallback" else this!!
fun <T> T.pipe(block: (T) -> T): T = block(this)
class Counter(var value: Int) {
    private fun add(n: Int): Int { value += n; return value }
    fun make(): (Int) -> Int = { n -> add(n) }
    fun Int.shift(): Int = this + value
    fun run(): Int = 2.shift()
}
class Outer(val n: Int) { fun score(): Int = n }
class Inner
class MemberPriority { fun pick(): Int = 5 }
fun exercise(): Int {
    val f: Outer.() -> Int = outer@ {
        val g: Inner.() -> Int = { score() + this@outer.n }
        g(Inner())
    }
    return f(Outer(7))
}
fun main() {
    println(21.twice())
    println(20.withOperation { this + 22 })
    println((null as String?).orFallback())
    val c = Counter(1)
    val change = c.make()
    println(change(2))
    println(c.run())
    val receiver: Int.(Int) -> Int = { other -> this + other }
    println(20.receiver(22))
    println(exercise())
    println(21.pipe { it * 2 })
    val pick: MemberPriority.() -> Int = { 99 }
    println(MemberPriority().pick())
    val increment: Int.() -> Int = { this + 1 }
    val escaped = { 41.increment() }
    println(escaped())
    val outer: Int.() -> Int = {
        val callback: Int.() -> Int = { this * 2 }
        val inner: Inner.() -> Int = { callback() }
        inner(Inner())
    }
    println(outer(21))
}
