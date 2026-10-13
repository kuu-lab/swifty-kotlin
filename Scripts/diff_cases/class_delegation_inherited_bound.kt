interface GenericBound<A> {
    fun <T : A> echo(value: T): T
}
open class GenericBase<B> {
    open fun <T : B> echo(value: T): T {
        println("base:generic")
        return value
    }
}
class InheritedBound : GenericBase<Number>(), GenericBound<Number>
class InheritedBoundDelegate(base: GenericBound<Number>) : GenericBound<Number> by base
fun main() {
    val delegate = InheritedBoundDelegate(InheritedBound())
    val control: GenericBound<Number> = delegate
    println(delegate.echo(7))
    println(control.echo(9))
}
