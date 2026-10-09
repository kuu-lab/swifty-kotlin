typealias Inter<TSubject, Call> = (Call) -> Unit
typealias Actions<T> = MutableList<Inter<Any, T>>

class Pipeline<TSubject : Any, Call : Any>(val actions: Actions<Call>) {
    constructor() : this(mutableListOf())
    constructor(label: String) : this()
}

class Named<T>(val label: String = "default", val actions: Actions<T>) {
    constructor() : this(actions = mutableListOf())
}

open class Base<T>(val actions: Actions<T>)

class Derived<U> : Base<U> {
    constructor() : super(mutableListOf())
}

class Plain<T>(val items: MutableList<T>) {
    constructor() : this(mutableListOf())
}

fun main() {
    val pipeline = Pipeline<Any, String>()
    println(pipeline.actions.size)
    pipeline.actions.add { value -> println("action:$value") }
    pipeline.actions[0]("hello")
    println(Pipeline<Any, String>("chain").actions.size)

    val named = Named<Int>()
    println(named.label)
    named.actions.add { value -> println(value + 1) }
    named.actions[0](41)

    val derived = Derived<String>()
    println(derived.actions.size)
    derived.actions.add { value -> println("super:$value") }
    derived.actions[0]("world")

    val plain = Plain<Int>()
    plain.items.add(7)
    println(plain.items[0])
}
