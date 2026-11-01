// KUU-3902: a value class stringified through an `Any`/nullable slot must
// print its synthesized rendering once — `IC(s=OK)` — not wrap the nominal
// box again (`IC(s=IC(s=…))`, which used to recurse through the erased
// `Any.toString` bridge). Every direct-call site — println, interpolation,
// concat, `.toString()`, data-class fields — must unbox the slot back to the
// payload the member ABI expects.
@JvmInline value class IC(val s: Any)
@JvmInline value class II(val i: Int)
@JvmInline value class S(val s: String)
@JvmInline value class N(val x: String?)
@JvmInline value class D(val d: Double)
class Holder(val name: String) { override fun toString() = "H($name)" }
@JvmInline value class R(val c: Holder)
@JvmInline value class W(val s: Any) { override fun toString() = "W<$s>" }
data class DC(val v: IC?)

fun main() {
    // Erased `Any` slots: the nominal/tagged box reaches kk_any_to_string.
    val ic: Any = IC("OK")
    println(ic)
    val ii: Any = II(42)
    println(ii)
    val s: Any = S("str")
    println(s)
    val n: Any = N("nullable")
    println(n)
    val n2: Any = N(null)
    println(n2)
    val r: Any = R(Holder("h"))
    println(r)
    val d: Any = D(1.5)
    println(d)
    val w: Any = W("w")
    println(w)

    // Non-null `V` slots already carry the payload representation.
    println(IC("direct"))
    println(II(7))
    println(S("ds"))
    println(N("dn"))
    println(R(Holder("dh")))
    println(D(2.5))

    // `V?` slots store the tagged/nominal box; println, interpolation,
    // concat and member calls must unbox before dispatching to V's own
    // toString.
    val icn: IC? = IC("nullable-slot")
    println(icn)
    println("interp: $icn")
    println("concat: " + icn)
    println(icn.toString())
    val i2: II? = II(9)
    println(i2)
    println("i2: $i2")
    println(i2.toString())
    val s2: S? = S("ns")
    println(s2)
    val n3: N? = N("nn")
    println(n3)
    val n4: N? = N(null)
    println(n4)
    val r2: R? = R(Holder("rh"))
    println(r2)
    println(DC(icn))
    val d2: D? = D(3.5)
    println(d2)

    // Null slots still render "null" through the same paths.
    val icnull: IC? = null
    println(icnull)
    val inull: II? = null
    println(inull)

    // Runtime-rendered containers hit the same nominal Any.toString bridge.
    println(listOf(icn))
    println(arrayOf(IC("e")).contentToString())

    // Payload reads and nominal equality are unaffected by rendering.
    println((ic as IC).s)
    println(icn?.s)
    println(ic == IC("OK"))
}
