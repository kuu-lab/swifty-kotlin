// KUU-3536: erased callable references must retain their FunctionN arity.
fun fn0() {}
fun fn1(x: Any) {}

fun main() {
    val f0 = ::fn0 as Any
    val f1 = ::fn1 as Any
    if (f0 !is Function1<*, *>) println("good") else println("BAD: Function0 seen as Function1")
    if (f1 !is Function0<*>) println("good") else println("BAD: Function1 seen as Function0")
}
