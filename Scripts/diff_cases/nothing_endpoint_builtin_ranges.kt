fun doubleRange(): ClosedFloatingPointRange<Double> = 1.0..error("missing end")
fun doubleRangeNothingLhs(): ClosedFloatingPointRange<Double> = error("missing end")..1.0
fun floatRange(): ClosedFloatingPointRange<Float> = 1.0f..error("missing end")
fun intRange(): IntRange = 1..error("missing end")
fun charRange(): CharRange = 'a'..error("missing end")
fun longRange(): LongRange = 1L..error("missing end")

fun main() {
    println("ok")
}
