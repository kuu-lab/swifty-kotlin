// KUU-3076: a bound property reference's `.get()` on a local receiver must not
// crash at runtime (previously SIGBUS from an invalid itable dispatch).
class C(val v: Int)

fun main() {
    val s: String = "x"
    println(s::length.get())
    println(s::length.invoke())
    val p = s::length
    println(p.get())
    val c = C(7)
    println(c::v.get())
    val t = "abc"
    var n = 0
    for (i in 1..t::length.get()) {
        n += 1
    }
    println(n)
}
