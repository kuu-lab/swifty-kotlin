import java.lang.ThreadLocal

class CountingLocal : ThreadLocal<Int>() {
    var inits = 0
    override fun initialValue(): Int {
        inits++
        return inits * 10
    }
}

fun main() {
    val r = ThreadLocal<Int>()
    r.set(5)
    println(r.get())
    r.set(6)
    println(r.get())

    val c = CountingLocal()
    println(c.get())
    println(c.get())
    c.set(99)
    println(c.get())
    c.remove()
    println(c.get())
    println(c.get())

    val w = ThreadLocal.withInitial { 42 }
    println(w.get())
    println(w.get())
    w.set(7)
    println(w.get())
}
