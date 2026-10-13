// KUU-1936: an initializer's interface delegation must not become property delegation.
interface Iface { fun f(): Int }
class Impl : Iface { override fun f() = 1 }

fun main() {
    val o = object {
        val inner = object : Iface by Impl() { }
        fun g() = inner.f()
    }
    println(o.g())
}
