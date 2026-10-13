interface Bounded {
    fun <T : CharSequence> echo(value: T): T
    fun <T : Number> echo(value: T): T
}
class BoundedImpl : Bounded {
    override fun <T : CharSequence> echo(value: T): T {
        println("impl:text")
        return value
    }
    override fun <T : Number> echo(value: T): T {
        println("impl:number")
        return value
    }
}
class BoundedDelegate(base: Bounded) : Bounded by base
class ExplicitBoundedDelegate(base: Bounded) : Bounded by base {
    override fun <T : Number> echo(value: T): T {
        println("override:number")
        return value
    }
}
open class BoundedBase : Bounded {
    override fun <T : CharSequence> echo(value: T): T {
        println("base:text")
        return value
    }
    override fun <T : Number> echo(value: T): T {
        println("base:number")
        return value
    }
}
class BoundedChild : BoundedBase() {
    override fun <T : Number> echo(value: T): T {
        println("child:number")
        return value
    }
}
interface Marker
class Marked : Marker
interface Generic<A> {
    fun <T : A> choose(value: T): T
}
class GenericImpl : Generic<Marker> {
    override fun <T : Marker> choose(value: T): T {
        println("generic:impl")
        return value
    }
}
class GenericDelegate<A>(base: Generic<A>) : Generic<A> by base
class SpecializedDelegate(base: Generic<Marker>) : Generic<Marker> by base {
    override fun <E : Marker> choose(value: E): E {
        println("generic:override")
        return value
    }
}
interface First
interface Second
class Both : First, Second
interface Multiple {
    fun <T> choose(value: T): T where T : First, T : Second
}
class MultipleImpl : Multiple {
    override fun <T> choose(value: T): T where T : First, T : Second {
        println("multiple:impl")
        return value
    }
}
class ReorderedDelegate(base: Multiple) : Multiple by base {
    override fun <E> choose(value: E): E where E : Second, E : First {
        println("multiple:override")
        return value
    }
}
interface Unbounded { fun <T> choose(value: T): T }
class UnboundedImpl : Unbounded {
    override fun <T> choose(value: T): T = value
}
class ExplicitAnyDelegate(base: Unbounded) : Unbounded by base {
    override fun <E : Any?> choose(value: E): E {
        println("any:override")
        return value
    }
}

fun main() {
    val concrete = BoundedDelegate(BoundedImpl())
    val control: Bounded = concrete
    val text: String = concrete.echo("text")
    val number: Int = concrete.echo(7)
    val controlText: String = control.echo("control")
    val controlNumber: Int = control.echo(9)
    println(text)
    println(number)
    println(controlText)
    println(controlNumber)
    val explicit = ExplicitBoundedDelegate(BoundedImpl())
    val explicitControl: Bounded = explicit
    println(explicit.echo("explicit"))
    println(explicit.echo(11))
    println(explicitControl.echo("interface"))
    println(explicitControl.echo(13))
    val inherited: BoundedBase = BoundedChild()
    println(inherited.echo("inherited"))
    println(inherited.echo(17))
    val generic = GenericDelegate<Marker>(GenericImpl())
    generic.choose(Marked())
    val genericControl: Generic<Marker> = generic
    genericControl.choose(Marked())
    val specialized = SpecializedDelegate(GenericImpl())
    specialized.choose(Marked())
    val specializedControl: Generic<Marker> = specialized
    specializedControl.choose(Marked())
    val reordered = ReorderedDelegate(MultipleImpl())
    reordered.choose(Both())
    val reorderedControl: Multiple = reordered
    reorderedControl.choose(Both())
    val any = ExplicitAnyDelegate(UnboundedImpl())
    println(any.choose(null))
    val anyControl: Unbounded = any
    println(anyControl.choose(null))
}
