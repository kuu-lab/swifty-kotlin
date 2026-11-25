// KUU-4608: in-place compound assignments (`plusAssign` etc.) do not rebind
// the local, so member smart casts on its stable receiver survive them.
class Box(val s: String?) {
    var calls = 0
    operator fun plusAssign(i: Int) { calls += i }
    operator fun minusAssign(i: Int) { calls -= i }
    operator fun timesAssign(i: Int) { calls *= i }
}

fun main() {
    var b = Box("hello")
    b += 2
    b -= 1
    b *= 3
    println(if (b.s != null) b.s.length else -1)
    println(b.calls)
    var c = Box(null)
    c += 1
    println(if (c.s != null) c.s.length else -1)
    println(c.calls)
}
