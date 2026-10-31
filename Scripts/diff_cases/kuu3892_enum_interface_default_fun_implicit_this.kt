// KUU-3892: an interface default `fun` invoked unqualified on `this` inside an
// enum class member bound directly to the interface default implementation,
// bypassing the `$enumEntryDispatch$` ordinal switch — the enum entry's own
// override was ignored (`E.X.test()` printed "F" instead of "XF").
interface Fun {
    fun f(): String = "F"
    fun g(x: Int = 7): String = "G$x"
}

enum class E : Fun {
    X { override fun f() = "XF" },
    Y;

    fun test() = f()
    fun testScoped() = with(this) { f() }
    fun testArg() = g(3)
    fun testDefault() = g()
    fun testSuper() = super<Fun>.f()
}

enum class D : Fun {
    A { override fun g(x: Int) = "AG$x" },
    B;

    fun testDefault() = g()
}

fun main() {
    // Unqualified `f()` on the enum `this` must reach the entry override.
    println(E.X.test())
    println(E.Y.test())
    // The same receiver through a receiver-scoped lambda.
    println(E.X.testScoped())
    // Arguments and omitted defaults still resolve against the entry impl.
    println(E.X.testArg())
    println(E.X.testDefault())
    // `super<Fun>` keeps static dispatch to the interface default.
    println(E.X.testSuper())
    // Entry override through the qualified and interface-typed paths.
    println(E.X.f())
    val i: Fun = E.X
    println(i.f())
    // A member overridden with a defaulted parameter keeps entry dispatch.
    println(D.A.testDefault())
    println(D.B.testDefault())
}
