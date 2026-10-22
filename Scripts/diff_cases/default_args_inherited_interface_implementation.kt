// DIFF_JVM
// KUU-2146: inherited concrete members use defaults from the leaf's interface scope.
interface LabelApi {
    fun label(value: String = "ok"): String
}
interface LabelChain : LabelApi
open class LabelImpl {
    fun label(value: String): String = "impl:$value"
}
class LabelLeaf : LabelImpl(), LabelChain {
    fun implicit(): String = label()
}

interface GenericApi<T> {
    val fallback: T
    fun value(input: T = fallback): T
}
open class GenericImpl<T> {
    open fun value(input: T): T = input
}
class GenericLeaf : GenericImpl<String>(), GenericApi<String> {
    override val fallback: String get() = "generic"
}

interface MethodApi {
    fun <T> method(input: T, count: Int = 1): T
}
open class MethodImpl {
    fun <U> method(input: U, count: Int): U = input
}
class MethodLeaf : MethodImpl(), MethodApi

interface CountApi { fun count(value: Int = 7): Any }
open class CountImpl { fun count(value: Int): Int = value }
class CountLeaf : CountImpl(), CountApi

interface NumericApi<T> { fun number(input: T, suffix: String = "!"): String }
open class NumericImpl { fun number(input: Int, suffix: String): String = "$input$suffix" }
class NumericLeaf : NumericImpl(), NumericApi<Int>

fun main() {
    val leaf = LabelLeaf()
    println(leaf.label())
    println(leaf.implicit())
    val nullable: LabelLeaf? = leaf
    println(nullable?.label())
    println(leaf.label(value = "named"))
    val api: LabelApi = leaf
    println(api.label())
    val base: LabelImpl = leaf
    println(base.label("base"))
    println(GenericLeaf().value())
    println(GenericLeaf().value(input = "explicit"))
    println(MethodLeaf().method("method"))
    println(CountLeaf().count())
    println(NumericLeaf().number(9))
}
