// KUU-3770: an anonymous context function with two same-typed context
// parameters type-checks against `context(S, S) () -> Unit`; invoking it
// through nested receivers supplies the nearest `S` for both context slots,
// matching kotlinc.
interface S { fun foo(c: Int) }

class Impl(val tag: String) : S {
    override fun foo(c: Int) { println("$tag$c") }
}

fun main() {
    val f: context(S, S) () -> Unit = context(s1: S, s2: S) fun() { s1.foo(2); s2.foo(3) }
    with(Impl("a")) {
        with(Impl("b")) {
            f()
        }
    }
    println("ok")
}
