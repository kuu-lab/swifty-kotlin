import kotlin.reflect.KCallable
import kotlin.reflect.KFunction

data class Person(val name: String, val age: Int)

fun <R, F> useK(c: F): String where F : KCallable<R> = c.name
fun <R, F> useKFn(c: F): String where F : KFunction<R> = c.name
fun <F> useKStar(c: F): String where F : KCallable<*> = c.name
fun <R> take(c: KCallable<R>): String = c.name
fun <T, R, F> having(subject: T, callable: F): String where F : (T) -> R, F : KCallable<R> = callable.name

fun inc(x: Int) = x + 1
fun greet(p: Person) = "hi ${p.name}"

fun main() {
    // KUU-4088: a callable reference satisfies a `F : KCallable<R>` /
    // `F : KFunction<R>` bound — the reference's return type binds R.
    println(useK(::inc))
    println(useKFn(::inc))
    println(useKStar(::inc))
    // The same decomposition covers a KCallable parameter type.
    println(take(::inc))
    // Property references are KCallable too (assertk `having` shape).
    println(useK(Person::name))
    val p = Person("ada", 36)
    println(having(p, Person::name))
    println(having(p, Person::age))
    println(having(p, ::greet))
}
