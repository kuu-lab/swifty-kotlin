fun trace(n: Int): Int { println(n); return n }
open class Parent(open val number: Int) {
    val copied = number
    init { println(copied) }
}
class Child(override val number: Int): Parent(number)
class Storage {
    var value = trace(1)
        get() { field += 1; return field }
        set(v) { field = v * 2 }
    init { value = 5; println(2) }
    val fixed: Int
    init { this.fixed = trace(3) }
    var raw: Int
        get() = field
    init { raw = 4 }
    constructor(n: Int) { value = n }
    constructor(): this(6) { value = 7 }
    fun readRaw(): Int = raw
}
fun main() {
    val child = Child(7)
    println(child.number)
    println(child.copied)
    val store = Storage()
    println(store.value)
    println(store.fixed)
    println(store.readRaw())
    store.value += 1
    println(store.value)
}
