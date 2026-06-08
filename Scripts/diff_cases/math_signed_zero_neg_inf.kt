import kotlin.math.*

fun main() {
    // Note: floor/truncate/cbrt signed-zero preservation (-0.0 → -0.0) is
    // validated at the Runtime layer in RuntimeMathEdgeCaseTests. Compiled
    // output does not yet preserve the sign bit of -0.0 literals through
    // these functions, so those checks live only in unit tests.

    // cbrt(-Inf) = -Inf
    println(cbrt(Double.NEGATIVE_INFINITY).isInfinite())  // true
    println(cbrt(Double.NEGATIVE_INFINITY) < 0)           // true

    // sinh(-Inf) = -Inf, cosh(-Inf) = +Inf, tanh(-Inf) = -1.0
    println(sinh(Double.NEGATIVE_INFINITY).isInfinite())  // true
    println(sinh(Double.NEGATIVE_INFINITY) < 0)           // true
    println(cosh(Double.NEGATIVE_INFINITY).isInfinite())  // true
    println(cosh(Double.NEGATIVE_INFINITY) > 0)           // true
    println(tanh(Double.NEGATIVE_INFINITY))               // -1.0

    // atanh(-1.0) = -Inf
    println(atanh(-1.0).isInfinite())    // true
    println(atanh(-1.0) < 0)            // true

    // tan(±Inf) = NaN
    println(tan(Double.POSITIVE_INFINITY).isNaN())  // true
    println(tan(Double.NEGATIVE_INFINITY).isNaN())  // true

    // atan2 符号付きゼロ / 負軸 / ±Inf special cases (IEEE 754 Annex F)
    // atan2(-0.0, positive) == -0.0 は Runtime 層でのみテスト (signed-zero 非保持)
    println(atan2(0.0, -1.0))                      // 3.141592653589793
    println(atan2(-0.0, -1.0))                     // -3.141592653589793
    println(atan2(Double.POSITIVE_INFINITY, 1.0))  // 1.5707963267948966
    println(atan2(Double.NEGATIVE_INFINITY, 1.0))  // -1.5707963267948966
    println(atan2(1.0, Double.POSITIVE_INFINITY))  // 0.0
    println(atan2(1.0, Double.NEGATIVE_INFINITY))  // 3.141592653589793
    println(atan2(Double.NaN, 1.0).isNaN())        // true
    println(atan2(1.0, Double.NaN).isNaN())        // true

    // nextUp(-Inf) / nextDown(+Inf)
    println(Double.NEGATIVE_INFINITY.nextUp())    // -1.7976931348623157E308
    println(Double.POSITIVE_INFINITY.nextDown())  // 1.7976931348623157E308

    // ulp(Float NaN) = NaN
    val fnan: Float = Float.NaN
    println(fnan.ulp.isNaN())            // true

    // sign(+0.0) = +0.0, sign(Float NaN) = NaN
    println(0.0.sign)                    // 0.0
    println(1.0 / 0.0.sign)             // Infinity (符号が + = 正の無限大)
    val fnan2: Float = Float.NaN
    println(fnan2.sign.isNaN())          // true
}
