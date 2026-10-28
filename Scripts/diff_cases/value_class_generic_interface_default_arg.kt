@JvmInline
value class IC(val s: String)

interface IFoo<T> {
    fun foo(x: T, s: String = "K"): String
}

class FooImpl : IFoo<IC> {
    override fun foo(x: IC, s: String): String = x.s + s
}

fun main() {
    val concrete = FooImpl()
    val generic: IFoo<IC> = concrete
    println(concrete.foo(IC("O")))
    println(generic.foo(IC("O")))
    println(concrete.foo(IC("O"), "!"))
    println(generic.foo(IC("O"), "!"))
}
