class Outer(private var value: Int) {
    private fun read(): Int = value
    inner class Inner(val extra: Int = value) {
        fun sum(): Int = read() + extra
        fun change(n: Int) { value = n }
        fun owner(): Outer = this@Outer
        inner class Deep { fun sum(): Int = this@Inner.sum() + this@Outer.read() }
    }
    fun make(): Inner = Inner()
}
class Names(val p0: Int) { inner class Inner(val p1: Int = p0, val p2: Int = p1 + 1) }
fun main() {
    println(Names(40).Inner().p2)
    val first = Outer(10)
    val second = Outer(20)
    val a = first.Inner(extra = 2)
    val b = second.make()
    println(a.sum()); println(b.sum())
    a.change(30)
    println(a.sum()); println(b.sum())
    println(a.owner() == first)
    println(a.Deep().sum())
}
