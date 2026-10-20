interface Named {
    val name: String
    fun label(): String = name
}
open class Base(val start: Int) {
    protected fun adjusted(value: Int): Int = value + start
    open fun score(): Int = start
}
class Counter(var count: Int): Base(count), Named {
    override val name: String = "counter"
    val doubled: Int get() = count * 2
    init { count += 1 }
    constructor(): this(10) { count += 2 }
    override fun score(): Int = super.score() + count
    fun add(n: Int): Int { count += n; return count }
    fun protectedCall(): Int = adjusted(count)
    private fun secret(): Int = 3
    fun privateCall(): Int = secret()
}
fun show(x: Named): String = x.label()
fun main() {
    val c = Counter()
    println(c.count)
    c.count = 20
    println(c.add(2))
    println(c.doubled)
    println(c.score())
    println(show(c))
    val b: Base = c
    println(b.score())
    println(c.protectedCall())
    println(c.privateCall())
}
