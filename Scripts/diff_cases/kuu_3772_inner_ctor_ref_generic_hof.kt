// KUU-3772: a bound constructor reference `::Inner` to a generic inner
// class inside a generic outer class, invoked through a generic
// higher-order function. The inferred return type of `createI` dropped
// the inner class's enclosing type arguments (bare `Inner` instead of
// `Outer<OT>.Inner<IT>`), so `ot2: OT` mis-resolved to Int and codegen
// emitted a claim-site cast + Int unbox on the String "x" — a runtime
// KSWIFTK-LINK-0003 panic. Fixed by #12252 (KUU-3874, enclosingTypeArgs
// preservation); this case pins the end-to-end behaviour.
public class Outer<OT>(val ot: OT) {
    inner class Inner<IT>(val it: IT, val ot2: OT)
    fun <II> createI(ii: II) = foo2(ii, ot, ::Inner)
}
fun <A, B, R> foo2(a: A, b: B, f: (A, B) -> R) = f(a, b)

fun main() {
    val o = Outer("x")
    val inner = o.createI(5)
    println(inner.ot2)
    println(inner.it)
    println(o.createI(7).ot2)
}
