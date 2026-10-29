// KUU-3629: a by-when delegation inside a top-level property initializer must
// keep the when body and the object literal body in the initializer expression.
interface C { fun f(): String }
object Impl : C { override fun f() = "OK" }
val o = object : C by when (true) { else -> Impl } {}

fun main() {
    println(o.f())
}
