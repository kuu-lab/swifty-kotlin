fun interface Action { fun run(value: String): String }
inline fun <reified T> cast(v: Any?): T = v as T
inline fun <reified T> identity(v: T): T = v
inline fun <reified T> label(sample: T, klass: kotlin.reflect.KClass<*> = T::class): String? = klass.simpleName
inline fun <reified U> factory(): (U) -> String? = ::label
interface Names { val eager: String; fun ref(): (Any?) -> Any? }
inline fun <reified T> names(): Names = object: Names {
    override val eager = T::class.java.name
    override fun ref(): (Any?) -> T = ::cast
}
fun main() {
    val action: Action = Action(::identity); println(action.run("sam"))
    println(factory<String>()("x")); println(factory<Int>()(1))
    val a: (String) -> String = ::identity; val b: (Int) -> Int = ::identity
    println(a == b)
    val n = names<Array<Int>>(); println(n.eager)
    println((n.ref()(arrayOf(1)) as Array<Int>)[0])
}
