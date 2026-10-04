// BUG-inner-outer: an object literal's member function reads an immutable
// property declared on a class reachable only through two `inner class`
// `$outer` hops (Deep -> Inner -> Outer). Capture analysis previously only
// considered the *immediate* enclosing class, so `value` was never
// recognized as captured and the read crashed / read garbage.
class Outer(val value: Int) {
    inner class Inner {
        inner class Deep {
            fun make(): Int {
                val obj = object {
                    fun compute(): Int {
                        return value + 1
                    }
                }
                return obj.compute()
            }
        }
    }
}

fun main() {
    val o = Outer(41)
    val i = o.Inner()
    val d = i.Deep()
    println(d.make())
}
