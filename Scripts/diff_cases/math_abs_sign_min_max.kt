import kotlin.math.*

// KSP-635: abs / sign / min / max overload matrix and the PI/E constants,
// now backed by bundled Kotlin source instead of synthetic stubs.
fun main() {
    // abs
    println(abs(-3.0))
    println(abs(-3.5f))
    println(abs(-7))
    println(abs(-7L))
    println(abs(Int.MIN_VALUE))
    println(abs(Long.MIN_VALUE))
    println(abs(Double.NEGATIVE_INFINITY))
    println(abs(Double.NaN).isNaN())
    println(1.0 / abs(-0.0))

    // absoluteValue
    println((-4.25).absoluteValue)
    println((-4.5f).absoluteValue)
    println((-9).absoluteValue)
    println((-9L).absoluteValue)

    // sign
    println(sign(5.0))
    println(sign(-5.0))
    println(sign(0.0))
    println(1.0 / sign(-0.0))
    println(sign(Double.NaN).isNaN())
    println(sign(2.5f))
    println(sign(-2.5f))
    println((-3.0).sign)
    println(3.0f.sign)
    println((-8).sign)
    println(8L.sign)
    println(0L.sign)

    // max / min: Double / Float
    println(max(1.0, 2.0))
    println(min(1.0, 2.0))
    println(max(1.5f, 2.5f))
    println(min(1.5f, 2.5f))
    println(max(Double.NaN, 1.0).isNaN())
    println(min(1.0, Double.NaN).isNaN())
    println(max(Float.NaN, 1.0f).isNaN())
    println(min(1.0f, Float.NaN).isNaN())
    println(1.0 / max(-0.0, 0.0))
    println(1.0 / min(-0.0, 0.0))
    println(1.0 / max(-0.0, -0.0))
    println(1.0f / max(-0.0f, 0.0f))
    println(1.0f / min(-0.0f, 0.0f))

    // max / min: integral
    println(max(3, 4))
    println(min(3, 4))
    println(max(Int.MIN_VALUE, Int.MAX_VALUE))
    println(min(Int.MIN_VALUE, Int.MAX_VALUE))
    println(max(3L, 4L))
    println(min(3L, 4L))
    println(max(3u, 4u))
    println(min(3u, 4u))
    println(max(1u, UInt.MAX_VALUE))
    println(min(1u, UInt.MAX_VALUE))
    println(max(3UL, 4UL))
    println(min(3UL, 4UL))
    println(max(1UL, ULong.MAX_VALUE))
    println(min(1UL, ULong.MAX_VALUE))

    // constants
    println(PI)
    println(E)
}
