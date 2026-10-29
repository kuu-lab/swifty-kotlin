// KUU-3674: capture-free callable references boxed for erased FunctionN invoke.
class A { companion object { fun foo() = "OK" } }
class B { companion object { fun foo() = "Fail" } }
class C { fun bar() = "member" }
fun B.foo() = "OK"
fun top(x: C) = "top"
fun call0(f: Any): String = (f as Function0<String>).invoke()
fun call1(f: Any): String = (f as Function1<B, String>).invoke(B())
fun call1c(f: Any): String = (f as Function1<C, String>).invoke(C())
fun main() {
    println(call0(A::foo))
    println(call1(B::foo))
    println(call1c(C::bar))
    println(call1c(::top))
    val lam: (B) -> String = { it.foo() }
    println(call1(lam))
}
