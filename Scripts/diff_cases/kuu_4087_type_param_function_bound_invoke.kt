// KUU-4087: a type parameter bounded by a function type is invocable through
// the bound's invoke signature — `c(t)` on `c: F` where `F : (T) -> R`.

fun <T, R, F> useFn(t: T, c: F): R where F : (T) -> R = c(t)
fun <T, R, F : (T) -> R> inlineBound(t: T, c: F): R = c(t)
fun <T, R, G : (T) -> R, F : G> chained(t: T, c: F): R = c(t)
fun <T, R, F : ((T) -> R)?> nullableBound(t: T, c: F): R? = c?.invoke(t)
fun <T, R, F : (T) -> R> explicitInvoke(t: T, c: F): R = c.invoke(t)
fun <A, B, R, F : (A, B) -> R> twoArg(a: A, b: B, c: F): R = c(a, b)
fun <F : ((Int) -> Int) -> Int> higherOrder(c: F): Int = c { it + 1 }

typealias IntFn = (Int) -> Int
fun <F : IntFn> viaAlias(c: F, x: Int): Int = c(x)

// The bound-bound value keeps winning over an in-scope function candidate of
// the same name that fails applicability.
fun c(x: String) = "top-level $x"
fun <T, R, F : (T) -> R> shadowed(t: T, c: F): R = c(t)

class Box<T, F : (T) -> T>(val t: T, val c: F) {
    fun go(): T = c(t)
    fun goExplicit(): T = c.invoke(t)
}

fun inc(x: Int) = x + 1
fun add(a: Int, b: Int) = a + b
fun twice(f: (Int) -> Int): Int = f(10) + f(20)

fun main() {
    println(useFn(2, ::inc))
    println(inlineBound(3, ::inc))
    println(chained(5, ::inc))
    println(nullableBound(7, ::inc))
    println(explicitInvoke(8, ::inc))
    println(twoArg(10, 20, ::add))
    println(higherOrder(::twice))
    println(viaAlias(::inc, 11))
    println(shadowed(4, ::inc))
    println(Box(9, ::inc).go())
    println(Box(9, ::inc).goExplicit())
    println(c("x"))
}
