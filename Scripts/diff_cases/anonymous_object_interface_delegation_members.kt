// KUU-1588: inherited members, overrides, storage, and enclosing-scope delegates.
interface Parent<T> {
    fun read(): T
    fun readDefault(): T = read()
    fun echo(value: T): T
    var value: T
}
interface Child<T> : Parent<T>
class Impl : Child<Int> {
    override fun read(): Int = value
    fun echo(value: String): String = "wrong overload"
    override fun echo(value: Int): Int = value
    override var value: Int = 7
}

interface Left { fun left(): Int }
interface Right { fun right(): Int }
class LeftImpl(val n: Int) : Left { override fun left(): Int = n }
class RightImpl : Right { override fun right(): Int = 20 }
open class Base(val base: Int)
interface Overloaded { fun call(value: Int): Int; fun call(value: String): String }
class OverloadedImpl : Overloaded {
    override fun call(value: Int): Int = value + 1
    override fun call(value: String): String = "text:" + value
}
class NamedWrapper : Overloaded by OverloadedImpl()
fun makeLeft(): Left {
    println("left delegate")
    return LeftImpl(10)
}
fun makeRight(): Right {
    println("right delegate")
    return RightImpl()
}
fun deferred(delegate: Left): () -> Left = {
    object : Left by delegate {}
}
class Holder(val delegate: Left) {
    fun deferred(): () -> Left = { object : Left by delegate {} }
}

fun main() {
    val impl = Impl()
    val offset = 2
    val o = object : Child<Int> by impl {
        val own = 40
        override fun read(): Int = own + offset
        fun extra(): Int = value
    }
    println(o.read())
    println(o.readDefault())
    println(o.echo(11))
    println(o.value)
    o.value = 9
    println(impl.read())
    val typed: Parent<Int> = o
    println(typed.read())
    println(typed.value)
    println(o.extra())
    println(o.readDefault())

    val multiple = object : Right by makeRight(), Left by makeLeft() {
        val initial = right() + left()
        init { println("object init") }
    }
    println(multiple.initial)
    println(multiple.right())
    println(multiple.left())

    var current: Left = LeftImpl(1)
    val stored = object : Left by current {}
    current = LeftImpl(2)
    println(stored.left())
    println(current.left())
    val factory = deferred(LeftImpl(3))
    println(factory().left())
    println(Holder(LeftImpl(4)).deferred()().left())
    val nested = object : Left by (object : Left by LeftImpl(5) {}) {}
    println(nested.left())
    val nestedProperty = object : Child<Int> by (object : Child<Int> by impl {}) {}
    println(nestedProperty.value)
    nestedProperty.value = 12
    println(impl.value)
    val mixed = object : Base(6), Left by LeftImpl(7) {}
    println(mixed.base + mixed.left())
    val conditional = object : Left by (if (offset < 3) LeftImpl(8) else LeftImpl(9)), Right by RightImpl() {
        fun marker(): Int = 6
    }
    println(conditional.left() + conditional.right() + conditional.marker())
    val overloads = object : Overloaded by OverloadedImpl() {}
    println(overloads.call(1))
    println(overloads.call("x"))
    val overriddenOverload = object : Overloaded by OverloadedImpl() {
        override fun call(value: Int): Int = value + 20
    }
    println(overriddenOverload.call(1))
    println(overriddenOverload.call("y"))
    println(NamedWrapper().call("named"))
}
