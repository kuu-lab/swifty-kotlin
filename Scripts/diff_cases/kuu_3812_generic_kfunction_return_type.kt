// KUU-3812: `KFunctionN.returnType` on a callable reference to a *generic*
// function needs an ABI-only adapter (erased parameter inputs), but the
// value still exposes KCallable reflection metadata. Previously the adapter
// hid KCallable identity, so `.returnType` fell back to an itable dispatch
// and crashed with KSWIFTK-RUNTIME-0001. The return type renders the literal
// type variable (`T`, `kotlin.Pair<T, U>`), matching JVM kotlin-reflect.
fun <T> foo(x: T) = x
fun <T, U> pair(a: T, b: U): Pair<T, U> = Pair(a, b)
fun plain(x: Int) = x + 1

fun main() {
    val bar: kotlin.reflect.KFunction1<Int, Int> = ::foo
    println(bar.returnType.toString())
    println(bar.parameters[0].type.toString())

    // A different instantiation of the same generic reference still renders
    // the declared type variable, not the written type argument.
    val asString: kotlin.reflect.KFunction1<String, String> = ::foo
    println(asString.returnType.toString())

    // Multi-parameter generic functions render nested type variables.
    val p: kotlin.reflect.KFunction2<Int, String, Pair<Int, String>> = ::pair
    println(p.returnType.toString())

    // Non-generic references keep qualified concrete rendering.
    val q: kotlin.reflect.KFunction1<Int, Int> = ::plain
    println(q.returnType.toString())
    println(bar.toString())
}
