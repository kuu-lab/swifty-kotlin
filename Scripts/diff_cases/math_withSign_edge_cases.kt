import kotlin.math.*

fun main() {
    // Negative zero must transfer its sign bit, producing a signed zero/magnitude value.
    println(3.0.withSign(-0.0))
    println((-3.0).withSign(0.0))
    println(3.0f.withSign(-0.0f))
    println((-3.0f).withSign(0.0f))

    // Int sign overloads.
    println(3.0.withSign(-1))
    println((-3.0).withSign(1))
    println(3.0f.withSign(-1))
    println((-3.0f).withSign(1))

    // NaN payloads keep magnitude but may adopt sign; verify the result is NaN.
    val nanNegative = Double.fromBits(Double.NaN.toRawBits() or Long.MIN_VALUE)
    val signed = 3.0.withSign(nanNegative)
    println(signed.isNaN())

    // Verify the sign of zero is propagated through Float division.
    val signedZero = 1.0f.withSign(-0.0f)
    println(signedZero == -0.0f)
    println(1.0f / signedZero < 0.0f)
}
