// KUU-3841: `is KFunctionN`/`is KSuspendFunctionN` erase to the KFunction
// classifier on the JVM — callable references satisfy every arity- and
// suspend-family check, while plain lambdas satisfy none of them.
import kotlin.reflect.KCallable
import kotlin.reflect.KFunction
import kotlin.reflect.KFunction1
import kotlin.reflect.KFunction2
import kotlin.reflect.KSuspendFunction0
import kotlin.reflect.KSuspendFunction1
import kotlin.reflect.KSuspendFunction2

suspend fun foo(x: Int): Int = x + 1
fun bar(x: Int): Int = x * 2
fun erase(value: Any?): Any? = value

fun main() {
    val f: suspend (Int) -> Int = ::foo
    println(f is KSuspendFunction1<*, *>)
    println(f is KSuspendFunction0<*>)
    println(f is KSuspendFunction2<*, *, *>)
    println(f is KFunction1<*, *>)
    println(f is KFunction<*>)
    println(f is KCallable<*>)
    val plain: (Int) -> Int = ::bar
    println(plain is KFunction1<*, *>)
    println(plain is KSuspendFunction1<*, *>)
    println(plain is KFunction<*>)
    val erased = erase(f)
    println(erased is KSuspendFunction1<*, *>)
    println(erased is KFunction2<*, *, *>)
    println((erased as? KSuspendFunction2<*, *, *>) != null)
    println((erased as? KFunction1<*, *>) != null)
    val lambda: suspend (Int) -> Int = { x -> x + 1 }
    println(erase(lambda) is KSuspendFunction1<*, *>)
    println(erase(lambda) is KFunction<*>)
    val g: KSuspendFunction1<Int, Int> = ::foo
    println(g.name)
    println((g as KFunction<*>).name)
}
