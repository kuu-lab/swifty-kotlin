interface Parent<T> {
    fun read(): T
    var value: T
}
interface Left<T> : Parent<T>
interface Right<T> : Parent<T>
interface Child<T> : Left<T>, Right<T>
class Impl : Child<Int> {
    override var value: Int = 7
    override fun read(): Int = value
}

var creations = 0
fun makeDelegate(): Child<Int> {
    creations++
    return Impl()
}
object Delegated : Child<Int> by makeDelegate() {
    init {
        println("init:" + read())
        println("value:" + value)
    }
    override fun read(): Int = 99
    fun localRead(): Int = value
    fun localWrite(newValue: Int) { value = newValue }
}
class Outer {
    class Nested<T>(delegate: Child<T>) : Child<T> by delegate
    object NestedObject : Child<Int> by Impl()
    companion object : Child<Int> by Impl()
}

fun main() {
    println(creations)
    println(Delegated.read())
    println(Delegated.value)
    println(Delegated.localRead())
    Delegated.localWrite(11)
    println(Delegated.value)
    val parent: Parent<Int> = Delegated
    parent.value = 12
    println(parent.read())
    println(Delegated.value)
    println(creations)
    val nested: Parent<Int> = Outer.Nested(Impl())
    nested.value = 13
    println(nested.read())
    println(Outer.NestedObject.read())
    Outer.NestedObject.value = 14
    val nestedObject: Parent<Int> = Outer.NestedObject
    println(nestedObject.read())
    println(Outer.read())
    Outer.value = 15
    val companion: Parent<Int> = Outer
    println(companion.read())
}
