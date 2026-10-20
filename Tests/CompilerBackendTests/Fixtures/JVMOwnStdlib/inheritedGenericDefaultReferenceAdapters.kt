interface Api<T> { fun number(input: T, suffix: String = "!"): String }
open class IntBase { open fun number(input: Int, suffix: String): String = "$input$suffix" }
// Declared overrides isolate adapter boxing from inherited bridge generation.
class IntLeaf: IntBase(), Api<Int> {
    override fun number(input: Int, suffix: String): String = super.number(input, suffix)
}
open class LongBase { open fun number(input: Long, suffix: String): String = "$input$suffix" }
class LongLeaf: LongBase(), Api<Long> {
    override fun number(input: Long, suffix: String): String = super.number(input, suffix)
}
open class DoubleBase { open fun number(input: Double, suffix: String): String = "$input$suffix" }
class DoubleLeaf: DoubleBase(), Api<Double> {
    override fun number(input: Double, suffix: String): String = super.number(input, suffix)
}
fun main() {
    val leaf = IntLeaf()
    val bound: (Int) -> String = leaf::number
    println(bound(9))
    val unbound: (IntLeaf, Int) -> String = IntLeaf::number
    println(unbound(leaf, 10))
    val api: Api<Int> = leaf
    val throughInterface: (Int) -> String = api::number
    println(throughInterface(11))
    val full: (Int, String) -> String = leaf::number
    println(full(12, "?"))
    val wideLong: (Long) -> String = LongLeaf()::number
    println(wideLong(21L))
    val wideDouble: (Double) -> String = DoubleLeaf()::number
    println(wideDouble(1.5))
}
