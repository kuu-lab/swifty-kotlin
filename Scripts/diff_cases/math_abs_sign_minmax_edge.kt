import kotlin.math.*

fun main() {
    println(abs(Int.MIN_VALUE))
    println(abs(Long.MIN_VALUE))
    println(abs(-0.0) == 0.0)
    println(1.0 / abs(-0.0))
    println(abs(Double.MIN_VALUE) == Double.MIN_VALUE)
    println(abs(Double.NEGATIVE_INFINITY))
    println(abs(Float.NEGATIVE_INFINITY))
    println(abs(Double.NaN).isNaN())
    println(abs(Float.NaN).isNaN())

    println(sign(Double.POSITIVE_INFINITY))
    println(sign(Double.NEGATIVE_INFINITY))
    println(sign(Double.NaN).isNaN())
    println(sign(Float.POSITIVE_INFINITY))
    println(sign(Float.NEGATIVE_INFINITY))
    println(sign(Float.NaN).isNaN())
    println(Int.MIN_VALUE.sign)
    println(Long.MAX_VALUE.sign)
    println(0.sign)

    println(max(Double.NaN, 1.0).isNaN())
    println(min(1.0, Double.NaN).isNaN())
    println(max(Float.NaN, 1.0f).isNaN())
    println(min(1.0f, Float.NaN).isNaN())
    println(max(Int.MIN_VALUE, Int.MAX_VALUE))
    println(min(Long.MIN_VALUE, Long.MAX_VALUE))
    println(max(1u, 4294967295u))
    println(min(1uL, 18446744073709551615uL))
}
