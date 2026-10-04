interface I { fun a(): String; val p: Int }
class X : I { override fun a() = "xa"; override val p = 1 }
class Y : I { override fun a() = "ya"; override val p = 2 }
open class Base { open fun n() = "base" }
class C1 : Base() { override fun n() = "c1" }
class C2 : Base() { override fun n() = "c2" }

fun main() {
    val ws = listOf(X(), Y())
    println(ws.map { it.a() })
    println(ws.map { it.p })
    val cs = listOf(C1(), C2())
    println(cs.map { it.n() })
    val pick = if (ws.size > 1) X() else Y()
    println(pick.a())
}
