object Counter {
    var value = 1
    val self = Counter
    val delayed: Int
    init { println("counter"); value += 1; delayed = 42 }
    fun add(n: Int): Int { value += n; return value }
}
class Factory private constructor(private val value: Int) {
    private fun read(): Int = value
    companion object Named {
        private val offset: Int
        init { offset = 20 }
        fun create(n: Int): Factory = Factory(n + offset)
        fun read(factory: Factory): Int = factory.read()
    }
}
fun main() {
    println(Counter.add(40))
    println(Counter.value)
    println(Counter.delayed)
    println(Counter == Counter.self)
    println(Factory.read(Factory.create(22)))
    println(Factory.Named.read(Factory.create(1)))
}
