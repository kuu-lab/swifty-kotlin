interface Echo {
    fun <T> echo(value: T): T
}
class EchoImpl : Echo {
    override fun <T> echo(value: T): T = value
}
class Delegate(base: Echo) : Echo by base

interface Generic<C> {
    fun <T : C> choose(value: T): T
    fun <A, B : A> second(first: A, value: B): B
    fun <T> echo(value: T): T
    fun echo(value: String): String
    fun <T> transform(value: T, operation: (T) -> T): T
}
class GenericImpl<C> : Generic<C> {
    override fun <T : C> choose(value: T): T = value
    override fun <A, B : A> second(first: A, value: B): B = value
    override fun <T> echo(value: T): T = value
    override fun echo(value: String): String = "text:$value"
    override fun <T> transform(value: T, operation: (T) -> T): T = operation(value)
}
interface Child<C> : Generic<C>
class ChildImpl<C> : Child<C>, Generic<C> by GenericImpl<C>()
class GenericDelegate<C>(base: Child<C>) : Child<C> by base
class OverrideDelegate<C>(base: Generic<C>) : Generic<C> by base {
    override fun <T> echo(value: T): T = value
}

interface Shadow<T> { fun <T> identity(value: T): T }
class ShadowImpl<T> : Shadow<T> {
    override fun <T> identity(value: T): T = value
}
class ShadowDelegate<T>(base: Shadow<T>) : Shadow<T> by base

fun main() {
    println(Delegate(EchoImpl()).echo(7))
    val concrete = Delegate(EchoImpl())
    val throughInterface: Echo = concrete
    val inferred: String = concrete.echo("inferred")
    println(inferred)
    println(concrete.echo<Long>(9L))
    println(throughInterface.echo(11))
    val generic = GenericDelegate<CharSequence>(ChildImpl<CharSequence>())
    val genericInterface: Generic<CharSequence> = generic
    println(generic.choose("bound"))
    println(generic.choose<String>("explicit"))
    println(genericInterface.choose("interface"))
    println(generic.second<CharSequence, String>("first", "second"))
    println(generic.echo(13))
    println(generic.echo("overload"))
    println(genericInterface.echo("interface overload"))
    println(generic.echo<String>("generic"))
    println(generic.transform(17) { it + 1 })
    println(OverrideDelegate<CharSequence>(GenericImpl<CharSequence>()).echo(19))
    println(ShadowDelegate<Int>(ShadowImpl<Int>()).identity("shadow"))
}
