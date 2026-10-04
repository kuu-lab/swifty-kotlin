// BUG-155: superclass constructors must run before subclass initializers, so
// inherited property initializers, `init` blocks and superclass constructor
// arguments are visible on subclass instances.

open class Base(val label: String) {
    var counter: Int = 7
    val derived: String = label + "!"

    init {
        counter = counter + 1
    }
}

class Child(label: String, val extra: Int) : Base(label) {
    var own: Int = 3
}

abstract class Shape {
    var sides: Int = 4
    abstract fun area(): Int
}

class Square(val side: Int) : Shape() {
    override fun area(): Int = side * side
}

open class Middle : Base("middle") {
    var middleFlag: Boolean = true
}

class Leaf : Middle()

open class NoPrimary {
    var value: Int = 11

    constructor() {
        value = value + 1
    }
}

class NoPrimaryChild : NoPrimary() {
    var childValue: Int = 21
}

open class Counter {
    var hits: Int = 0
}

class SecondaryOnly : Counter {
    var name: String = "secondary"

    constructor() : super() {
        hits = hits + 5
    }

    constructor(extra: Int) : this() {
        hits = hits + extra
    }
}

class ThisDelegating {
    var initialized: Int = 100

    constructor() : this(1)

    constructor(bump: Int) {
        initialized = initialized + bump
    }
}

// The `AbstractIterator` state machine shape that surfaced BUG-155: a generic
// superclass storing a value into a `T?` field. The bundled stdlib class
// itself cannot be subclassed through a prebuilt `.kklib` (BUG-183), so the
// same shape is declared locally here.
abstract class ValueHolderIterator<T> {
    private var ready = false
    private var nextValue: T? = null

    fun hasNext(): Boolean {
        if (ready) return true
        computeNext()
        return ready
    }

    @Suppress("UNCHECKED_CAST")
    fun next(): T {
        if (!hasNext()) throw NoSuchElementException()
        ready = false
        val result = nextValue as T
        nextValue = null
        return result
    }

    protected abstract fun computeNext(): Unit

    protected fun setNext(value: T): Unit {
        nextValue = value
        ready = true
    }

    protected fun done() {
        ready = false
    }
}

class OneShot(private val v: Int) : ValueHolderIterator<Int>() {
    private var used = false

    override fun computeNext() {
        if (used) {
            done()
        } else {
            used = true
            setNext(v)
        }
    }
}

fun main() {
    val child = Child("root", 5)
    println(child.label)
    println(child.derived)
    println(child.counter)
    println(child.extra)
    println(child.own)

    val square = Square(3)
    println(square.sides)
    println(square.area())

    val leaf = Leaf()
    println(leaf.label)
    println(leaf.counter)
    println(leaf.middleFlag)

    val noPrimary = NoPrimaryChild()
    println(noPrimary.value)
    println(noPrimary.childValue)

    val secondary = SecondaryOnly()
    println(secondary.hits)
    println(secondary.name)
    println(SecondaryOnly(10).hits)

    println(ThisDelegating().initialized)

    val iterator = OneShot(42)
    while (iterator.hasNext()) {
        println(iterator.next())
    }
}
