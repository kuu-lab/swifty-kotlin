// KUU-3616: a boxed value class's ==/equals is nominal on the JVM — the
// operands must be the same value class for payloads to compare, so
// `(A("x") as Any) == "x"` is false even though the payloads match.
// kotlinc rejects `==` between a value class and a different concrete type
// outright, so cross-type probes go through `as Any`/`Any?` slots here.
@JvmInline
value class A(val x: String)

@JvmInline
value class I(val x: Int)

class C(val v: Int)

@JvmInline
value class R(val c: C)

@JvmInline
value class N(val x: String?)

@JvmInline
value class D(val x: Double)

data class DC(val v: Int)

fun main() {
    val s: A = A("x")
    val t: Any? = "x"

    // A boxed value class never equals a raw value of its underlying type.
    println(s == t)
    println(t == s)
    println((s as Any) == "x")
    println("x" == (s as Any))
    println((I(1) as Any) == 1)
    println(1 == (I(1) as Any))
    println(s != t)

    // The same nominal value class still compares by payload.
    println(s == A("x"))
    println(A("x") == s)
    println(I(1) == I(1))
    println(s != A("y"))
    println((s as Any) == A("x"))
    val a1: Any = s
    val a2: Any = A("x")
    println(a1 == a2)
    println(a1 === a1)
    println(a1 === a2)

    // equals() uses the same nominal bridge.
    println(s.equals(t))
    println(s.equals("x"))
    println(s.equals(A("x")))
    println(I(1).equals(1))
    println(I(1).equals(I(1)))
    println(s.equals(null))

    // A different nominal class never matches on payload alone.
    println((I(1) as Any) == DC(1))
    println(DC(1) == (I(1) as Any))

    // Heterogeneous collection lookups never unwrap the key's tag.
    val m: Map<Any?, String> = hashMapOf(I(1) to "v")
    println(m[1])
    println(m[I(1)])
    val set: Set<Any?> = setOf(I(7))
    println(set.contains(1))
    println(set.contains(I(7)))
    println(listOf(I(3)).contains(I(3)))
    println(listOf<Any?>(I(3)).contains(3))

    // Reference-payload value classes wrap nominally too.
    val c = C(1)
    val r = R(c)
    println(r == (c as Any))
    println(r == R(c))
    println((r as Any) == c)

    // Nullable-underlying value classes keep wrapper identity distinct.
    val n = N("x")
    println(n == ("x" as Any))
    println(n == N("x"))
    println(N(null) == null)
    println(N(null) != null)

    // Sentinel-colliding underlying primitives stay nominal as well.
    println(D(1.5) == (1.5 as Any))
    println(D(1.5) == D(1.5))
    println(D(-0.0) == D(0.0))
    val d2: D? = D(1.5)
    println(d2 == (1.5 as Any))
    println(d2 == D(1.5))

    // Null handling is unchanged.
    println(s == null)
    println(null == s)
    val sn: A? = null
    println(sn == s)
    println(sn == null)
    val snn: A? = A("x")
    println(snn == s)
    println(snn == ("x" as Any))
}
