// BUG-141: reading an interface's stored/abstract property through an
// interface-typed receiver (object expression, named class, function
// parameter, or custom getter) must dispatch to the implementing getter via
// the interface itable instead of emitting an unresolved symbol.
interface Holder {
    val value: Int
}

interface Named {
    val name: String
}

class Impl : Holder {
    override val value: Int = 42
}

class Computed : Holder {
    override val value: Int
        get() = 7
}

fun makeObject(): Holder = object : Holder {
    override val value: Int = 1
}

fun makeObjectComputed(): Holder = object : Holder {
    override val value: Int
        get() = 2
}

fun readHolder(h: Holder): Int = h.value

fun makeNamed(): Named = object : Named {
    override val name: String = "kotlin"
}

fun main() {
    println(makeObject().value)
    println(makeObjectComputed().value)
    println(readHolder(Impl()))
    println(readHolder(Computed()))
    val h: Holder = Impl()
    println(h.value)
    println(makeNamed().name)
}
