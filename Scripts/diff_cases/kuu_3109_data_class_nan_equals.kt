// KUU-3109: synthesized data class equals must use Double.equals/Float.equals
// semantics — NaN equals NaN regardless of payload, while -0.0 differs from
// +0.0 — not raw bit-pattern equality.
data class D(val x: Double)
data class F(val x: Float)
data class Mix(val d: Double, val i: Int, val s: String)
fun main() {
    val a = Double.fromBits(0x7ff8000000000001L)
    val b = Double.fromBits(0x7ff8000000000002L)
    println(a.isNaN())
    println(D(a) == D(b))
    println(D(a).hashCode() == D(b).hashCode())
    val c = Float.fromBits(0x7fc00001)
    val d = Float.fromBits(0x7fc00002)
    println(c.isNaN())
    println(F(c) == F(d))
    println(F(c).hashCode() == F(d).hashCode())
    println(D(-0.0) == D(0.0))
    println(D(-0.0) == D(-0.0))
    println(F(-0.0f) == F(0.0f))
    println(D(1.5) == D(1.5))
    println(D(1.5) == D(2.5))
    println(D(Double.NaN) == D(Double.NaN))
    println(D(Double.POSITIVE_INFINITY) == D(Double.POSITIVE_INFINITY))
    println(Mix(a, 1, "x") == Mix(b, 1, "x"))
    println(Mix(a, 1, "x") != Mix(b, 1, "x"))
}
