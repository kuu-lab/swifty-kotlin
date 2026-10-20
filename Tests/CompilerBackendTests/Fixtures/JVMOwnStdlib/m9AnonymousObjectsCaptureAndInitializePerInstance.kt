interface Counter { fun next(): Int }
open class Base(val seed: Int = 10) { open fun next(): Int = seed }
fun counter(start: Int): Counter {
    var n = start
    val first = object: Counter { override fun next(): Int { n++; return n } }
    val second = object: Counter { override fun next(): Int { n += 10; return n } }
    first.next()
    second.next()
    return first
}
class Owner(private var n: Int) {
    private fun read(): Int = n
    fun make(): Counter = object: Counter {
        override fun next(): Int { n++; return read() }
    }
}
fun main() {
    val a = counter(0); val b = counter(100)
    println(a.next()); println(b.next()); println(a.next())
    var local = 2
    val x = object: Base(seed = local + 1), Counter {
        val initial = local
        init { local += 10 }
        override fun next(): Int = super.next() + local + initial
        fun own(): Int = initial
    }
    println(x.next()); println(x.own()); println(local)
    val owner = Owner(20)
    val c = owner.make(); val d = owner.make()
    println(c.next()); println(d.next())
    val anonymous = object { val answer = 42; fun read(): Int = answer }
    println(anonymous.read())
}
