// KUU-4487: calling `toString()` through an abstract/sealed receiver used
// to return null because the `kotlin.Any.toString` vtable slot mixed two
// ABIs — a flat String aggregate for Kotlin overrides and a raw handle for
// the runtime fallback. The slot now always stores the raw
// `kk_any_member_to_string` dispatcher, which resolves the most-derived
// override through the Any-toString registry.

sealed class Kuu4487Sealed
class Kuu4487Impl(val v: Int) : Kuu4487Sealed() {
    override fun toString() = "A$v"
    override fun hashCode() = 111
    override fun equals(other: Any?) = other is Kuu4487Impl
}
class Kuu4487NoOverride(val v: Int) : Kuu4487Sealed()

abstract class Kuu4487Abs
class Kuu4487ImplD(val v: Int) : Kuu4487Abs() {
    override fun toString() = "D$v"
    override fun hashCode() = 222
}
class Kuu4487NoToString(val v: Int) : Kuu4487Abs()

open class Kuu4487Open(val v: Int) {
    override fun toString() = "O$v"
}
class Kuu4487SubOpen(v: Int) : Kuu4487Open(v)

interface Kuu4487Named { fun name(): String }
class Kuu4487ImplN(val v: Int) : Kuu4487Named {
    override fun name() = "N$v"
    override fun toString() = "N$v"
}

abstract class Kuu4487A3
data class Kuu4487DC(val v: Int) : Kuu4487A3()

open class Kuu4487WithToString {
    override fun toString() = "W"
}
data class Kuu4487DC2(val v: Int) : Kuu4487WithToString()

sealed class Kuu4487SealedOwn {
    override fun toString() = "SealedBase"
}
class Kuu4487SealedChild : Kuu4487SealedOwn() {
    override fun toString() = "SealedChild"
}
class Kuu4487SealedNoOwn : Kuu4487SealedOwn()

open class Kuu4487ErrBase(msg: String) : Exception(msg)
class Kuu4487ErrSub(msg: String) : Kuu4487ErrBase(msg) {
    override fun toString() = "SubErr:$message"
}
class Kuu4487ErrPlain(msg: String) : Kuu4487ErrBase(msg)

fun <T : Kuu4487Abs> showGeneric(t: T): String = t.toString()

fun main() {
    val a: Kuu4487Sealed = Kuu4487Impl(1)
    println("A.toString=" + a.toString())
    println("A.hashCode=" + a.hashCode())
    println("A.equals=" + a.equals(Kuu4487Impl(1)))

    val b: Kuu4487Sealed = Kuu4487NoOverride(2)
    println("B.hasClassName=" + b.toString().startsWith("Kuu4487NoOverride@"))

    val d: Kuu4487Abs = Kuu4487ImplD(3)
    println("D.toString=" + d.toString())
    println("D.hashCode=" + d.hashCode())

    val e: Kuu4487Abs = Kuu4487NoToString(4)
    println("E.hasClassName=" + e.toString().startsWith("Kuu4487NoToString@"))

    val o: Kuu4487Open = Kuu4487SubOpen(5)
    println("O.toString=" + o.toString())

    val n: Kuu4487Named = Kuu4487ImplN(6)
    println("N.toString=" + n.toString())

    val any: Any = Kuu4487Impl(7)
    println("Any.toString=" + any.toString())
    println("Any.hashCode=" + any.hashCode())

    val x: Kuu4487A3 = Kuu4487DC(9)
    println("DC.toString=" + x.toString())
    val y: Kuu4487WithToString = Kuu4487DC2(8)
    println("DC2.toString=" + y.toString())

    val s: Kuu4487SealedOwn = Kuu4487SealedChild()
    println("S1=" + s.toString())
    val s2: Kuu4487SealedOwn = Kuu4487SealedNoOwn()
    println("S2=" + s2.toString())

    val t1: Kuu4487ErrBase = Kuu4487ErrSub("x")
    println("T1=" + t1.toString())
    val t2: Kuu4487ErrBase = Kuu4487ErrPlain("y")
    println("T2=" + t2.toString())

    println("G1=" + showGeneric(Kuu4487ImplD(1)))
    println("G2=" + showGeneric(Kuu4487NoToString(2)).startsWith("Kuu4487NoToString@"))
}
