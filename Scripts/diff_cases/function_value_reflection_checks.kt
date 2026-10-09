// KUU-1230: function values retain their FunctionN and reflection identities.
fun topFn(a: Int) = a + 1
fun erase(value: Any?): Any? = value
fun returnedReference(): (Int) -> Int = ::topFn
class Offset(val n: Int) {
    fun add(x: Int): Int = n + x
}
fun main() {
    val g: (Int) -> Int = { it + 1 }
    val h = { x: Int -> x + 1 }
    val q: (Int) -> Int = ::topFn
    println(g is Function1<*, *>)
    println(h is Function1<*, *>)
    println(q is Function1<*, *>)
    println(::topFn is kotlin.reflect.KFunction<*>)
    println(::topFn is kotlin.reflect.KCallable<*>)
    val lambda = erase(g)
    println(lambda is Function1<*, *>)
    println(lambda is kotlin.reflect.KFunction<*>)
    println(lambda is kotlin.reflect.KCallable<*>)
    val reference = erase(returnedReference())
    println(reference is Function1<*, *>)
    println(reference is Function2<*, *, *>)
    println(reference is kotlin.reflect.KFunction<*>)
    println(reference is kotlin.reflect.KCallable<*>)
    println((reference as? kotlin.reflect.KFunction<*>) != null)
    println((reference as kotlin.reflect.KCallable<*>).name)
    println((reference as Function1<Int, Int>)(3))
    val bound = erase(Offset(10)::add)
    println(bound is Function1<*, *>)
    println(bound is kotlin.reflect.KFunction<*>)
    println(bound is kotlin.reflect.KCallable<*>)
    println((bound as Function1<Int, Int>)(2))
    val unbound = erase(Offset::add)
    println(unbound is Function2<*, *, *>)
    println(unbound is kotlin.reflect.KFunction<*>)
    println(unbound is kotlin.reflect.KCallable<*>)
    println((unbound as Function2<Offset, Int, Int>)(Offset(20), 2))
    println(erase(null) is kotlin.reflect.KCallable<*>)
    println(erase(123) is kotlin.reflect.KCallable<*>)
    println(erase("x") is Function1<*, *>)
}
