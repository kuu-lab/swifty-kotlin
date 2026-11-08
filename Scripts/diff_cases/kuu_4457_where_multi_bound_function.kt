// KUU-4457: a type variable declared with multiple upper bounds
// (`where F : (T) -> R, F : KCallable<R>`) must satisfy a parameter typed as
// one of its bounds — here `callable` is passed where `(T) -> R` is expected,
// while `callable.name` resolves through the KCallable<R> bound.
import kotlin.reflect.KCallable

class Assert<T>(val v: T)

fun <T, R> Assert<T>.having(name: String?, callable: (T) -> R): Assert<R> = Assert(callable(v))

fun <T, R, F> Assert<T>.having(callable: F): Assert<R>
    where F : (T) -> R, F : KCallable<R> =
    having(callable.name, callable)

fun main() {
    println(Assert(1).having(Int::inc).v)
}
