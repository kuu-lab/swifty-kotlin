// KUU-1318: non-property constructor parameters remain in scope in init blocks,
// including member access after superclass constructor delegation.
class Wrap(val inner: Int)

class B(d: Wrap) {
    init {
        if (d.inner < 2) println("small")
    }
}

open class Base(val value: Int)

class Derived(d: Wrap) : Base(d.inner) {
    val copied = d.inner
    var initialized = 0

    init {
        if (d.inner < 2) println("derived small")
        initialized = d.inner + value
    }

    init {
        println(d.inner)
    }
}

fun main() {
    B(Wrap(1))
    B(Wrap(3))
    val first = Derived(Wrap(1))
    println(first.value)
    println(first.copied)
    println(first.initialized)
    val second = Derived(Wrap(3))
    println(second.value)
    println(second.copied)
    println(second.initialized)
}
