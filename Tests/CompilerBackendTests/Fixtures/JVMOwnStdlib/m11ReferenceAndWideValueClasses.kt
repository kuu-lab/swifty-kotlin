@JvmInline value class Text(val value: String)
@JvmInline value class OptionalText(val value: String?)
@JvmInline value class Wide(val value: Long)
@JvmInline value class Real(val value: Double)
fun text(v: Text?): Text? = v
fun optional(v: OptionalText?): OptionalText? = v
fun wide(v: Wide): Wide = Wide(v.value + 1L)
fun real(v: Real): Real = v
fun main() {
    println(text(null)); println(text(Text("hello")))
    println(optional(null)); println(optional(OptionalText(null)))
    println(wide(Wide(9000000000L))); println(real(Real(2.5)))
    val nan = Real(0.0 / 0.0)
    println(nan == Real(0.0 / 0.0)); println(Real(0.0) == Real(-0.0))
    println(Text::class.isValue); println(Wide::class.simpleName)
}
