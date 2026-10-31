// KUU-3786: an unchecked cast into a generic superclass erases the type
// argument, so a `T`-bounded member used inside the callee can receive an
// object that violates the bound. Kotlin/JVM inserts `checkcast` on the
// member's declaring type for the erased receiver, producing a catchable
// ClassCastException — without it the native vtable/itable lookup indexed
// a foreign layout and trapped (`Virtual dispatch failed`).
// Mirrors kotlin/testData/codegen/box/casts/uncheckedCast8.kt.
interface I1
interface I2 { val z: Int }
interface I3 { var w: Int }
open class Bound { open fun member(): Int = 7 }
open class Base<T : I1> { open fun call(x: T): I1 = x }
open class Contra<in T : I1> { open fun call(x: T): I1 = x }
open class NullableBase<T : I1> { open fun call(x: T?): I1? = x }

class IfaceGet<T> : Base<T>() where T : I1, T : I2 {
    override fun call(x: T): I1 { println(x.z); return x }
}
class IfaceSet<T> : Base<T>() where T : I1, T : I3 {
    override fun call(x: T): I1 { x.w = 9; println(x.w); return x }
}
class ClassBound<T> : Base<T>() where T : I1, T : Bound {
    override fun call(x: T): I1 { println(x.member()); return x }
}
class ContraBound<in T> : Contra<T>() where T : I1, T : I2 {
    override fun call(x: T): I1 { println(x.z); return x }
}
class SafeBound<T> : NullableBase<T>() where T : I1, T : I2 {
    override fun call(x: T?): I1? { println(x?.z); return x }
}

class Wrong : I1
class GetD : I1, I2 { override val z = 42 }
class SetD : I1, I3 { override var w = 5 }
class ClassD : I1, Bound()

fun main() {
    println(try { (IfaceGet<GetD>() as Base<Wrong>).call(Wrong()); "FAIL" }
        catch (e: ClassCastException) { "iface-get OK" })
    println(try { (IfaceSet<SetD>() as Base<Wrong>).call(Wrong()); "FAIL" }
        catch (e: ClassCastException) { "iface-set OK" })
    println(try { (ClassBound<ClassD>() as Base<Wrong>).call(Wrong()); "FAIL" }
        catch (e: ClassCastException) { "class-bound OK" })
    println(try { (ContraBound<GetD>() as Contra<Wrong>).call(Wrong()); "FAIL" }
        catch (e: ClassCastException) { "contra-bound OK" })
    println(try { (SafeBound<GetD>() as NullableBase<Wrong>).call(Wrong()); "FAIL" }
        catch (e: ClassCastException) { "safe-bound OK" })
    // Valid receivers still dispatch through the same erased boundary.
    (IfaceGet<GetD>() as Base<GetD>).call(GetD())
    (ClassBound<ClassD>() as Base<ClassD>).call(ClassD())
    (IfaceSet<SetD>() as Base<SetD>).call(SetD())
}
