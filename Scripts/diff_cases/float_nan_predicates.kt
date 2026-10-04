// KSP-646: isNaN / isInfinite / isFinite are implemented in bundled Kotlin via
// IEEE 754 bit-pattern checks. Cover the edge cases that the bit-pattern form
// must get right: signed zeros, subnormals, NaN produced by arithmetic, NaN
// with a non-canonical payload, and the boundary exponent values.

fun classify(value: Double): String = when {
    value.isNaN() -> "nan"
    value.isInfinite() -> "inf"
    else -> "finite"
}

fun classify(value: Float): String = when {
    value.isNaN() -> "nan"
    value.isInfinite() -> "inf"
    else -> "finite"
}

fun main() {
    // Signed zeros and subnormals are finite.
    println(classify(0.0))
    println(classify(-0.0))
    println(classify(Double.MIN_VALUE))
    println(classify(-Double.MIN_VALUE))
    println(classify(Double.MAX_VALUE))
    println(classify(-Double.MAX_VALUE))

    // Infinities.
    println(classify(Double.POSITIVE_INFINITY))
    println(classify(Double.NEGATIVE_INFINITY))
    println(classify(1.0 / 0.0))
    println(classify(-1.0 / 0.0))

    // NaN from arithmetic and from an explicit bit pattern with a payload.
    println(classify(0.0 / 0.0))
    println(classify(Double.POSITIVE_INFINITY - Double.POSITIVE_INFINITY))
    println(classify(Double.fromBits(0x7FF0000000000001L)))
    println(classify(-Double.fromBits(0x7FF00000000ABCDEL)))

    // Float mirrors the Double behaviour.
    println(classify(0.0f))
    println(classify(-0.0f))
    println(classify(Float.MIN_VALUE))
    println(classify(Float.MAX_VALUE))
    println(classify(Float.POSITIVE_INFINITY))
    println(classify(Float.NEGATIVE_INFINITY))
    println(classify(Float.NaN))
    println(classify(Float.fromBits(0x7F800001)))
    println(classify(1.0f / 0.0f))

    // Exactly one predicate must hold for every value.
    val samples = listOf(
        0.0,
        -0.0,
        1.5,
        -1.5,
        Double.MIN_VALUE,
        Double.MAX_VALUE,
        Double.POSITIVE_INFINITY,
        Double.NEGATIVE_INFINITY,
        Double.NaN
    )
    for (sample in samples) {
        var held = 0
        if (sample.isNaN()) held += 1
        if (sample.isInfinite()) held += 1
        if (sample.isFinite()) held += 1
        println(held)
    }

    // isFinite is the negation of (isNaN or isInfinite).
    for (sample in samples) {
        println(sample.isFinite() == !(sample.isNaN() || sample.isInfinite()))
    }

    // NaN is never equal to itself, but the predicate is still true.
    val nan = Double.NaN
    println(nan == nan)
    println(nan.isNaN())
    println(nan != nan && nan.isNaN())
}
