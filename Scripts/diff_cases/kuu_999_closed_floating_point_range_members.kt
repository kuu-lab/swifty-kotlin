fun main() {
    val r = 0.0..1.0
    println(r.start)
    println(r.endInclusive)
    println(r.isEmpty())
    println(r.toString())
    println((1.0..0.0).isEmpty())

    val f = 0.0f..1.0f
    println(f.start)
    println(f.endInclusive)
    println(f.isEmpty())
    println(f.toString())
    println((1.0f..0.0f).isEmpty())

    val doubleRange: ClosedFloatingPointRange<Double> = -1.25..2.5
    val doubleStart: Double = doubleRange.start
    val doubleEnd: Double = doubleRange.endInclusive
    println(doubleStart)
    println(doubleEnd)
    println(doubleEnd - doubleStart)
    println(doubleRange.isEmpty())
    println(doubleRange.toString())
    val doubleAlias = doubleRange
    println(doubleAlias.start)
    println(doubleAlias.endInclusive)

    val floatRange: ClosedFloatingPointRange<Float> = -1.25f..2.5f
    val floatStart: Float = floatRange.start
    val floatEnd: Float = floatRange.endInclusive
    println(floatStart)
    println(floatEnd)
    println(floatEnd - floatStart)
    println(floatRange.isEmpty())
    println(floatRange.toString())
    val floatAlias = floatRange
    println(floatAlias.start)
    println(floatAlias.endInclusive)

    println((-2.5..-1.25).start)
    println((-2.5f..-1.25f).endInclusive)
    println((1.0..1.0).isEmpty())
    println((1.0f..1.0f).isEmpty())
    println((Double.NaN..1.0).start)
    println((0.0..Double.NaN).endInclusive)
    println((Double.NaN..1.0).isEmpty())
    println((0.0..Double.NaN).isEmpty())
    println((Float.NaN..1.0f).start)
    println((0.0f..Float.NaN).endInclusive)
    println((Float.NaN..1.0f).isEmpty())
    println((0.0f..Float.NaN).isEmpty())
    println((Double.NEGATIVE_INFINITY..Double.POSITIVE_INFINITY).start)
    println((Double.NEGATIVE_INFINITY..Double.POSITIVE_INFINITY).endInclusive)
    println((Float.NEGATIVE_INFINITY..Float.POSITIVE_INFINITY).start)
    println((Float.NEGATIVE_INFINITY..Float.POSITIVE_INFINITY).endInclusive)
    println((-0.0..0.0).start)
    println((-0.0f..0.0f).start)
    println((1..3).start)
    println((1L..3L).endInclusive)
}
