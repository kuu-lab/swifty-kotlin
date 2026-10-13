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
