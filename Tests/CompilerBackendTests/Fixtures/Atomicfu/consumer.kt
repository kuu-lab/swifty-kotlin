import atomicfuproducer.*
fun main() {
    val counter = newCounter()
    println(counter.bump())
    println(counter.value)
    println(element().getAndIncrement())
    val nullable = nullableCounter()
    println(nullable.getAndSet(5))
    println(nullable.getAndSet(null))
    println(nullable.value)
    println(nextGlobal())
    println(nextGlobal())
}
