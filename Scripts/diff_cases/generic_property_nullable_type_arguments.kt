fun <X> makeIt(x: X): X = x

class Factory {
    fun <X> makeIt(x: X): X = x
}

class Box<T>(val value: T)

class Pool<T : Any>(val factory: Factory, val optional: Factory?) {
    private var instance = makeIt<T?>(null)
    private val member = factory.makeIt<T?>(null)
    private val safeMember = optional?.makeIt<T?>(null)
    private val nested = makeIt<Box<T?>>(Box<T?>(null))

    fun get(): T? = instance
    fun put(value: T) { instance = makeIt<T?>(value) }
    fun unchanged(value: T): T = makeIt<T>(value)
    fun printInitialValues() {
        println(instance)
        println(member)
        println(safeMember)
        println(nested.value)
    }
}

fun main() {
    val factory = Factory()
    val ints = Pool<Int>(factory, factory)
    ints.printInitialValues()
    ints.put(42)
    println(ints.get())
    println(ints.unchanged(7))
    val strings = Pool<String>(factory, null)
    strings.printInitialValues()
    strings.put("ready")
    println(strings.get())
    println(strings.unchanged("ok"))
}
