// KUU-4086: a value class stored into an `Any?`/`Any` field or parameter must
// keep its nominal box. `VC(VC(5))` must print `VC(VC(5))`, not `VC(5)`.
@JvmInline
value class VC(val v: Any?) {
    override fun toString() = "VC($v)"
}

class Holder(val v: Any?)

fun takeAny(a: Any?): Any? = a

class Box<T>(val t: T)

fun main() {
    println(VC(5))               // VC(5)
    println(VC(VC(5)))           // VC(VC(5))
    println(VC(VC(VC(1))))       // VC(VC(VC(1)))
    val a: Any = VC(7)
    println(a)                   // VC(7)
    val h = Holder(VC(8))
    println(h.v)                 // VC(8)
    println(takeAny(VC(9)))      // VC(9)
    val x: Any? = VC(10)
    println(x)                   // VC(10)
    val list: List<Any?> = listOf(VC(11))
    println(list[0])             // VC(11)

    // is / as round-trips through Any
    val e: Any = VC(VC(3))
    println(e is VC)             // true
    println(e as VC)             // VC(VC(3))
    println((e as? VC)?.v)       // VC(3)
    println(e)                   // VC(VC(3))

    // generic container
    val b = Box(VC(12))
    println(b.t)                 // VC(12)

    // equals / hashCode on boxed VC
    val p: Any = VC(4)
    val q: Any = VC(4)
    println(p == q)              // true
    println(p.hashCode() == q.hashCode()) // true
    println(VC(4) == VC(4))      // true
    println(VC(4).hashCode() == VC(4).hashCode()) // true
}
