// KUU-2361: preserve the upstream inherited IFoo<Unit> SAM specialization.
fun interface IFoo<T> {
    fun foo(): T
}

fun interface IFooUnit : IFoo<Unit> {
    override fun foo()
}

fun <T> fooT(iFoo: IFoo<T>) = iFoo.foo()
fun fooUnit(iFooUnit: IFooUnit) { iFooUnit.foo() }

var ok = "Failed"

fun box(): String {
    fooT { ok = "O" }
    fooUnit { ok += "K" }
    return ok
}

fun main() {
    println(box())
}
