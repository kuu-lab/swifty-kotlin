fun <T> anyVararg(vararg x: T): Boolean = x[0] == 123f
fun boxingNullablePrimitiveToAny(x: Float?) = x !== null && anyVararg(x)
fun boxingPrimitiveToAny(x: Float) = anyVararg(x)
value class InlineFloat(val value: Float)
fun <T : InlineFloat> valueClassAnyVararg(vararg x: T): Boolean = x[0].value == 123f
fun boxingInlineClassToAny(x: InlineFloat) = valueClassAnyVararg(x)

fun main() {
    println(boxingPrimitiveToAny(123f))
    println(boxingNullablePrimitiveToAny(123f))
    println(boxingNullablePrimitiveToAny(null))
    println(boxingInlineClassToAny(InlineFloat(123f)))
}
