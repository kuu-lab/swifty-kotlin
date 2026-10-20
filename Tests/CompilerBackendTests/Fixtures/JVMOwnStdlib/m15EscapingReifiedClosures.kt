inline fun <reified T> predicate(): (Any?) -> Boolean = { it is T }
inline fun <reified T> caster(): (Any?) -> T? = { it as? T }
inline fun <reified T: Any> token(): () -> String = { T::class.java.name }
inline fun <reified T> factory(): (Int) -> Array<T?> = { arrayOfNulls<T>(it) }
inline fun <reified T> unsafe(): (Any?) -> T = { it as T }
inline fun <reified T: Number> bounded(n: Int): Array<T?> = arrayOfNulls<T>(n)
inline fun <reified T> nested(): () -> ((Any?) -> Boolean) = { predicate<T>() }
inline fun <reified T> arrays(): (Any?) -> Boolean = predicate<Array<T>>()
fun main() {
    val p = predicate<Int>(); println(p(1)); println(p("wrong")); println(p(null))
    val nullable = predicate<String?>(); println(nullable(null)); println(nullable("yes")); println(nullable(1))
    val c = caster<Int>(); println(c(7)); println(c("wrong"))
    println(token<Int>()()); println(factory<String>()(2).javaClass.name)
    try { unsafe<String>()(null) } catch (e: NullPointerException) { println("null cast") }
    try { unsafe<String>()(1) } catch (e: ClassCastException) { println("bad cast") }
    println(bounded<Int>(1).javaClass.name)
    println(nested<String>()()("yes")); println(arrays<Int>()(arrayOf(1))); println(arrays<Int>()(arrayOf("wrong")))
}
