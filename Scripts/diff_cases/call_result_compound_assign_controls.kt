class Counter {
    var value = 0
    operator fun plusAssign(delta: Int) { value += delta }
    operator fun plusAssign(delta: String) { value += delta.length }
    operator fun minusAssign(delta: Int) { value -= delta }
    operator fun timesAssign(delta: Int) { value *= delta }
    operator fun divAssign(delta: Int) { value /= delta }
    operator fun remAssign(delta: Int) { value %= delta }
    operator fun plus(delta: Int): Counter = Counter()
}

class Factory(val counter: Counter) {
    var calls = 0
    fun get(): Counter { calls++; return counter }
    fun get(ignored: Int): Counter { calls++; return counter }
}

fun create(factory: Factory): Counter = factory.get()
fun delta(factory: Factory): Int { println(factory.calls); return 6 }

fun smartCastRhs(value: Int?): Int {
    create(Factory(Counter())) += value!!
    return value
}

fun smartCastLhs(value: Int?): Int {
    Factory(Counter()).get(value!!) += 1
    return value
}

fun main() {
    val scopes = ArrayDeque<MutableMap<String, Boolean>>()
    scopes.add(mutableMapOf())
    val scope = scopes.last()
    scope += "x" to true
    println(scopes.last()["x"])

    val counter = Counter()
    val factory = Factory(counter)
    factory.get() += delta(factory)
    factory.get() += "ab"
    factory.get(0) -= 2
    create(factory) *= 4
    factory.get() /= 3
    factory.get() %= 5
    factory.counter += 2
    var number = 3
    number += 4
    println(counter.value)
    println(factory.calls)
    println(number)
    println(smartCastRhs(4))
    println(smartCastLhs(5))
}
