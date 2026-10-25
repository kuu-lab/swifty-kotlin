// KUU-3108: synthesized data class equals must compare nullable primitive
// properties by value, not by box identity — Int?/Long?/Double?/Float? and
// friends box at the nullable boundary, so a raw pointer compare reports
// equal values as unequal.
data class D(val x: Double?)
data class F(val x: Float?)
data class I(val x: Int?)
data class L(val x: Long?)
data class M(val a: Int?, val d: Double?, val s: String?)
fun main() {
    println(D(1.5) == D(1.5))
    println(I(1000) == I(1000))
    println(D(null) == D(null))
    println(D(-0.0) == D(null))
    println(D(Double.NaN) == D(Double.NaN))
    val pa = Double.fromBits(0x7ff8000000000001L)
    val pb = Double.fromBits(0x7ff8000000000002L)
    println(D(pa) == D(pb))
    println(F(Float.NaN) == F(Float.NaN))
    println(F(-0.0f) == F(0.0f))
    println(L(Long.MIN_VALUE) == L(Long.MIN_VALUE))
    println(L(null) == L(Long.MIN_VALUE))
    println(I(null) == I(0))
    println(M(1, 2.0, "x") == M(1, 2.0, "x"))
    println(M(null, null, null) == M(null, null, null))
    println(D(1.5).hashCode() == D(1.5).hashCode())
    println(I(1000).hashCode() == I(1000).hashCode())
}
