@JvmInline value class V(val value: Int)
inline fun <reified T> cast(v: Any?): T = v as T
inline fun <reified T> safe(v: Any?): T? = v as? T
inline fun <reified T> identity(v: T): T = v
inline fun <reified T> defaulted(v: T, n: Int = 2): T = v
inline fun <reified T> forward(): (Any?) -> T = ::cast
inline fun <reified T> T.token(): String = T::class.java.name
class Holder(val n: Int) { inline fun <reified T> same(v: T): T = v }
var evaluations = 0
fun owner(): Holder { evaluations++; return Holder(evaluations) }
fun main() {
    val text: (Any?) -> String = ::cast; println(text("yes"))
    val number: (Int) -> Int = ::identity; println(number(21))
    val nullable: (Any?) -> String? = ::cast; println(nullable(null))
    val safe: (Any?) -> Int? = ::safe; println(safe("wrong")); println(safe(42))
    val v: (Any?) -> V = ::cast; println(v(V(8)).value)
    val a: (Any?) -> Array<String> = ::cast; println(a(arrayOf("item"))[0])
    val member: (String) -> String = owner()::same; println(member("bound")); println(evaluations)
    val unbound: (Holder, Int) -> Int = Holder::same; println(unbound(Holder(1), 7))
    val ext: (String) -> String = String::token; println(ext("value"))
    val bound: () -> String = "value"::token; println(bound())
    val default: (String) -> String = ::defaulted; println(default("default")); println(default is kotlin.reflect.KFunction<*>)
    val unit: () -> Unit = "value"::token; unit(); println(unit is kotlin.reflect.KFunction<*>)
    println(forward<String>()("escaped")); println(forward<Int?>()(null))
    try { text(null) } catch (e: NullPointerException) { println("null") }
    try { text(1) } catch (e: ClassCastException) { println("cast") }
    println((text as kotlin.reflect.KFunction<*>).name); println((text as kotlin.reflect.KFunction<*>).isInline)
}
