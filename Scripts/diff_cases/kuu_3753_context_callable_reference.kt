// KUU-3753: an unbound callable reference must satisfy an expected function
// type whose context parameter stands in for the receiver
// (`context(A) () -> T` accepts `A::instance`, `A::ext`, `A::p`).

class A {
    fun instance() = true
    val p = true
}

fun A.ext() = true

val A.extp: Boolean get() = true

fun take(f: context(A) () -> Boolean) { }

fun callContext(f: context(A) () -> Boolean, receiver: A) = f(receiver)

fun main() {
    val a = A()
    take(A::instance)
    take(A::ext)
    take(A::p)
    take(A::extp)
    println(callContext(A::instance, a))
    println(callContext(A::ext, a))
    println(callContext(A::p, a))
    println(callContext(A::extp, a))
}
