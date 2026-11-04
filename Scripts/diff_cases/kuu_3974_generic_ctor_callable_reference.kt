// KUU-3974: an MVIKotlin-style `::BypassExecutor` reference passed to a
// generic call must map the class type parameters onto the call's own
// inference variables. Leaking the class's lexical parameters used to
// produce conflicting bounds (`B.I <: T <: B.I`) and reject the program.
interface Executor<I, S> {
    fun tag(): String
}

class Bypass<I : Any, S : Any>(val name: String) : Executor<I, S> {
    constructor() : this("bypass")
    constructor(name: String, unused: Int) : this(name)
    override fun tag(): String = name
}

fun <I : Any, S : Any> create(executorFactory: () -> Executor<I, S>, s: S): () -> Executor<I, S> = executorFactory
fun <I : Any, S : Any> createBoth(executorFactory: () -> Executor<I, S>, i: I, s: S) = executorFactory

interface SingleExecutor<I> {
    fun id(): Int
}

class OneParam<I : Any>(val x: Int) : SingleExecutor<I> {
    constructor() : this(0)
    constructor(s: String) : this(s.length)
    override fun id(): Int = x
}

fun <I : Any> createOne(executorFactory: () -> SingleExecutor<I>) = executorFactory

fun main() {
    // S is pinned by the sibling argument; I is resolved from the bound.
    val inferred = create(::Bypass, 0)
    println(inferred().tag())

    // Both call type parameters are pinned by sibling arguments.
    val both = createBoth(::Bypass, "x", 1)
    println(both().tag())

    // Explicit call type arguments.
    val explicit = create<String, Int>(::Bypass, 2)
    println(explicit().tag())

    // Overloaded constructors: `() -> SingleExecutor<I>` picks `constructor()`.
    val one = createOne<Int>(::OneParam)
    println(one().id())
}
