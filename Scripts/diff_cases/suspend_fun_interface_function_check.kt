// A fun interface (or any class) inheriting `suspend () -> T` is also a
// Function1 on the JVM, however the instance was created: a callable
// reference, a lambda, or an explicit object.
fun interface SuspendCallable : suspend () -> String
fun interface SuspendCallable1 : suspend (Int) -> String

suspend fun target(): String = "ok"
suspend fun target1(x: Int): String = "ok$x"

fun wrap(f: SuspendCallable): Any = f
fun wrap1(f: SuspendCallable1): Any = f

class Impl : suspend () -> String {
    override suspend fun invoke(): String = "impl"
}

fun main() {
    val fromRef = wrap(::target)
    val fromLambda = wrap { "ok" }
    val fromObject: Any = object : SuspendCallable { override suspend fun invoke(): String = "x" }
    val fromClass: Any = Impl()
    val arity1 = wrap1(::target1)
    for (value in listOf(fromRef, fromLambda, fromObject, fromClass)) {
        println("${value is Function1<*, *>} ${value is Function0<*>} ${value is Function2<*, *, *>}")
    }
    println("${arity1 is Function2<*, *, *>} ${arity1 is Function1<*, *>}")
}
