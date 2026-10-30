// KUU-3793: an override spelled with a rigid type parameter must not steal
// the itable slot of an unrelated interface signature. `foo(t: T)` overrides
// `A<T>.foo` only; `B.foo(Int)` keeps its default — on the JVM the erased
// `foo(Object)` never overrides `foo(int)`, and substituting T=Int during
// reified inline expansion must not change that (JetBrains
// `reified/overrideResolution.kt` shape).
interface A<T> { fun foo(t: T) = "A" }
interface B { fun foo(t: Int) = "B" }

private inline fun <reified T> makeB(): B = object : A<T>, B {
    override fun foo(t: T) = "make"
}
private inline fun <reified T> makeA(): A<T> = object : A<T>, B {
    override fun foo(t: T) = "make"
}

class C<T> : A<T>, B {
    override fun foo(t: T) = "C"
}

fun main() {
    println(makeB<Int>().foo(42))
    println(makeA<Int>().foo(7))
    val c: B = C<Int>()
    println(c.foo(42))
    val ca: A<Int> = C<Int>()
    println(ca.foo(9))
}
