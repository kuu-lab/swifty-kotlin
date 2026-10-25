@JvmInline
value class S(val x: String)

@JvmInline
value class M(val v: Int)

@JvmInline
value class N(val x: Int?)

@JvmInline
value class R(val ref: Holder)

class Holder(val name: String)

fun main() {
    // KUU-3251: a nullable value class whose underlying type is a non-null
    // reference (String) carries the tagged value-class box. Reading the
    // field through `?.` must unwrap the payload, not alias the box.
    val str = "s"
    val s: S? = S(str)

    // The shared payload variable must stay a plain String: tagging the box
    // in place would dispatch S.toString here.
    println(str)

    // Safe-call field reads return the underlying payload.
    println(s?.x)
    println(s?.x?.length)
    println(s!!.x)

    // The unwrapped field is the payload object itself (identity preserved).
    println(s?.x === str)
    println(s?.x === "s")
    println(s?.x == "s")

    // Rendering the tagged handle still dispatches the value-class members.
    println(s)
    println(s?.toString())

    // Erased dispatch through Any.
    val a: Any = s!!
    println(a is S)
    println(a)
    println(a.toString())

    // Safe-cast into the value class, then safe-call the field.
    val sa: Any? = s
    println((sa as? S)?.x)

    // Null receiver.
    val n: S? = null
    println(n?.x)

    // Primitive-underlying value class regression check.
    val m: M? = M(42)
    println(m?.v)
    println(m)

    // Nullable-underlying value class (nominal-box representation).
    val n1: N? = N(7)
    println(n1?.x)
    println(N(7) == n1)
    val n2: N? = N(null)
    println(n2?.x)
    val n3: N? = null
    println(n3?.x)
    println(n1)

    // Reference-type underlying: V? slots carry the raw reference.
    val rr = Holder("shared")
    val r: R? = R(rr)
    println(r?.ref?.name)
    println(r?.ref === r?.ref)
    println(rr.name)
    println(r?.ref === rr)
}
