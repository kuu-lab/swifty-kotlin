// KUU-3681: A generic interface override must box value-class return values.

@JvmInline
value class X(val x: Any)

interface IFoo<T> {
    fun foo(): T
}

class T2 : IFoo<X> {
    override fun foo(): X = X("O")
}

fun main() {
    val t: IFoo<X> = T2()
    val r: Any = t.foo()
    println(r is X)
    println((r as X).x)
}
