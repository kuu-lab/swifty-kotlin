// KUU-4487: explicit Any-member calls (toString/hashCode/equals) on receivers
// whose static type is an abstract/sealed/open base must dispatch to the
// concrete override. They previously went through vtable slots resolved from
// kotlin.Any's layout, which do not line up with subclass vtable numbering —
// e.g. nominals rooted at an empty-vtable superclass number their own members
// from slot 0, so the lookup hit an unrelated method or returned null.

sealed class K4487Base
class K4487ImplA(val v: Int) : K4487Base() { override fun toString() = "A$v" }
class K4487ImplB(val s: String) : K4487Base() { override fun toString() = "B$s" }

open class K4487Open { override fun toString() = "open" }
class K4487ImplC(val v: Int) : K4487Open() { override fun toString() = "C$v" }

abstract class K4487Abs
class K4487ImplD(val v: Int) : K4487Abs() { override fun toString() = "D$v" }
open class K4487Mid : K4487Abs()
class K4487Leaf : K4487Mid() { override fun toString() = "leaf" }

enum class K4487Color { RED, GREEN }
object K4487Singleton {
    override fun toString() = "Singleton!"
}

data class K4487Point(val x: Int, val y: Int)

abstract class K4487Eq
class K4487EqImpl(val v: Int) : K4487Eq() {
    override fun equals(other: Any?) = other is K4487EqImpl && other.v == v
    override fun hashCode() = v * 31
    override fun toString() = "Eq$v"
}

fun <T : K4487Abs> k4487Pick(t: T): String = t.toString()

fun main() {
    val a: K4487Base = K4487ImplA(1)
    val b: K4487Base = K4487ImplB("x")
    println(a.toString())
    println(b.toString())
    println("${a}")
    println(a.hashCode() == a.hashCode())
    println(a.equals(a))
    println(a.equals(b))

    val c: K4487Open = K4487ImplC(2)
    println(c.toString())

    val d: K4487Abs = K4487ImplD(3)
    println(d.toString())

    val l: K4487Abs = K4487Leaf()
    println(l.toString())
    println(k4487Pick(K4487Leaf()))

    val ca: Any = K4487Color.GREEN
    println(ca.toString())
    val sa: Any = K4487Singleton
    println(sa.toString())

    val p: Any = K4487Point(1, 2)
    println(p.toString())
    println(K4487Point(1, 2).equals(K4487Point(1, 2)))

    val e: K4487Eq = K4487EqImpl(5)
    println(e.toString())
    println(e.equals(K4487EqImpl(5)))
    println(e.equals(K4487EqImpl(6)))
    println(e.hashCode())
}
