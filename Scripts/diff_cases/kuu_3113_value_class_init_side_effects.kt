// KUU-3113: value-class constructor must keep executing init blocks.
var count = 0
var log = ""

@JvmInline
value class V(val x: Int) {
    init { count += x }
}

@JvmInline
value class W(val s: String) {
    init { log += "W" }
}

@JvmInline
value class P(val x: Int)  // no init: stays unboxed

@JvmInline
value class D(val x: Int = 9) {
    init { count += 100 }
}

fun take(v: V): Int = v.x
fun idV(v: V): V = v

fun main() {
    val v = V(3)
    println(v.x)
    println(count)
    println(take(v))
    println(idV(v).x)
    println(count)

    val w = W("a")
    println(w.s)
    println(log)

    val p = P(7)
    println(p.x)

    val d1 = D()
    println(d1.x)
    val d2 = D(4)
    println(d2.x)
    println(count)

    val f = ::V
    val v2 = f(5)
    println(v2.x)
    println(count)

    println(v == V(3))
    println(count)
    var mv = V(1)
    mv = V(2)
    println(mv.x)
    println(count)
}
