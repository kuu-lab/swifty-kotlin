import kotlin.math.*

fun main() {
    // KSP-637: public transcendental functions must resolve through bundled
    // Kotlin source while retaining the libm edge-case behavior.
    println(sin(0.0) == 0.0)
    println(cos(0.0) == 1.0)
    println(tan(0.0) == 0.0)
    println(asin(1.0) > 1.57 && asin(1.0) < 1.58)
    println(acos(1.0) == 0.0)
    println(atan(0.0) == 0.0)
    println(atan2(1.0, 0.0) > 1.57 && atan2(1.0, 0.0) < 1.58)

    println(exp(0.0) == 1.0)
    println(expm1(0.0) == 0.0)
    println(ln(1.0) == 0.0)
    println(ln1p(0.0) == 0.0)
    println(log(8.0, 2.0) == 3.0)
    println(log2(8.0) == 3.0)
    println(log10(100.0) == 2.0)

    println(sinh(0.0) == 0.0)
    println(cosh(0.0) == 1.0)
    println(tanh(0.0) == 0.0)
    println(acosh(1.0) == 0.0)
    println(asinh(0.0) == 0.0)
    println(atanh(0.0) == 0.0)
    println(cbrt(-8.0) == -2.0)
    println(hypot(3.0, 4.0) == 5.0)
    println(sqrt(4.0) == 2.0)
    println(2.0.pow(3.0) == 8.0)
    println(2.0.pow(3) == 8.0)
    println(7.0.IEEErem(2.5) == -0.5)
    println(1.0.nextTowards(2.0) > 1.0)

    val floatValue: Float = 2.0f
    println(sin(floatValue) > 0.90f && sin(floatValue) < 0.91f)
    println(sqrt(4.0f) == 2.0f)
    println(log(8.0f, 2.0f) == 3.0f)
    println(cbrt(-8.0f) == -2.0f)

    // Domain and infinity boundaries.
    println(sin(Double.POSITIVE_INFINITY).isNaN())
    println(ln(0.0).isInfinite())
    println(log(-1.0, 2.0).isNaN())
    println(atanh(1.0).isInfinite())
    println(cbrt(Double.NEGATIVE_INFINITY).isInfinite())
    println(hypot(Double.POSITIVE_INFINITY, Double.NaN).isNaN())
}
