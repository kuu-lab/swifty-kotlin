// KUU-3611: a tailrec member function with a default argument inside an
// anonymous object used as a default parameter value must emit its
// `g$default` stub so the object's `foo` override can call `g(true)`
// through it. Previously the stub was missing and linking failed with
// `"_g$default", referenced from: ..._ObjectLiteral_0..._foo`.
interface IFoo { fun foo() = "OK" }

tailrec fun f(b: Boolean, x: IFoo = object : IFoo {
    tailrec fun g(c: Boolean, y: IFoo = object : IFoo {}): String =
        if (c) g(false) else y.foo()
    override fun foo() = g(true)
}): String = if (b) f(false) else x.foo()

fun main() { println(f(true)) }
