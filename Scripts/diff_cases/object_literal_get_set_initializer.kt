interface Iface { fun f(): Int }
fun get(x: Int): Int = x * 10
fun set(x: Int): Int = x + 100
fun get(block: () -> Int): Int = block()
infix fun Int.choose(other: Int): Int = this + other

fun main() {
    val o = object : Iface {
        val a = get(1)
        val b = set(2)
        override fun f() = a + b
    }
    println(o.f())

    val plain = object {
        val total = get(1) + set(2)
        val nested = (get(1)) + run { set(2) }
        val typedGet: Int = get(1)
        val typedSet: Int = set(2)
        val comparison = 2 > get() { 1 }
        val conditional = if (true) 1 else if (false) get() { 2 } else 3
        val infix = 1 choose get() { 2 }
        val trailing = get() { 5 }
        var raw = 3
        var value: Int
            get() = get(raw)
            set(v) { raw = set(v) }
    }
    println(plain.total)
    println(plain.nested)
    println(plain.typedGet + plain.typedSet)
    println(plain.comparison)
    println(plain.conditional)
    println(plain.infix)
    println(plain.trailing)
    println(plain.value)
    plain.value = 4
    println(plain.value)
}
