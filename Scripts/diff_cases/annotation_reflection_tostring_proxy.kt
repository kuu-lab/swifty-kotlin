// KUU-4418: reflection-materialized annotation instances render through the
// JVM AnnotationInvocationHandler proxy format — members in memberValues
// order (defaulted members in HashMap order, then required members in
// declaration order), String/Char quoted, arrays as `{a, b}`, KClass as
// `<name>.class`, and nested annotations recursively in proxy format —
// while directly constructed instances keep the bare kotlinc-style
// rendering.
annotation class M(val z: String = "d", val a: Int = 7)
annotation class Arr(val names: Array<String>)
annotation class K(val k: kotlin.reflect.KClass<*>)
annotation class Outer(val inner: M, val tag: String)
annotation class Mixed(val a: Int, val b: Int = 5, val c: String)
annotation class Defs(val p: String = "p", val q: Int, val r: Boolean = true)
enum class E { CLASS }
annotation class Full(val e: E, val nums: IntArray, val k: kotlin.reflect.KClass<*>, val flag: Boolean = true)
annotation class Wrap(val items: Array<M>)

@M @Arr(arrayOf("p", "r")) @K(String::class) @Outer(M(z = "q", a = 2), "t")
@Mixed(1, c = "c") @Defs(q = 9, p = "z") @Full(E.CLASS, intArrayOf(4, 5), Int::class)
@Wrap(arrayOf(M(z = "x", a = 1), M()))
class C

fun main() {
    for (a in C::class.annotations) println(a)
    println("---")
    println(M())
    println(Arr(arrayOf("p", "r")))
    println(Outer(M(z = "q", a = 2), "t"))
    println(Mixed(1, c = "c"))
    println(Defs(q = 9, p = "z"))
    println(Full(E.CLASS, intArrayOf(4, 5), Int::class))
    println(Wrap(arrayOf(M(z = "x", a = 1), M())))
}
