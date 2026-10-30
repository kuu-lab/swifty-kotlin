// KUU-3794: an infix call whose receiver is a bare `f()` invocation and
// whose argument is a plain identifier must not absorb the next line into
// the same statement (the trailing identifier was misjudged as a pending
// infix name, so the following statement was dropped).
val LOG = 5
fun topFun() = 32
fun rootSize() = 16

fun main() {
    val x = topFun() shr LOG
    println(x)
    val local = 4
    val y = rootSize() shr local
    println(y)
    val r = topFun() until LOG
    println(r.last)
    val p = topFun() to LOG
    println(p.first)
    val f = ::topFun
    val z = f() shr LOG
    println(z)
}
