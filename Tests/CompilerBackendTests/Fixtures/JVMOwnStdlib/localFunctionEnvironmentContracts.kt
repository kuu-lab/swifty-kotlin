interface ShadowValue { fun value(): Int }
fun lambdaShadow() {
    val x = 1
    fun read(): Int = x
    if (true) {
        val x = 2
        val delayed = { read() }
        println(delayed())
        println(x)
    }
}
fun objectShadow() {
    val x = 3
    fun read(): Int = x
    if (true) {
        val x = 4
        val delayed = object: ShadowValue { override fun value(): Int = read() }
        println(delayed.value())
        println(x)
    }
}
fun localChainShadow() {
    val x = 5
    fun read(): Int = x
    if (true) {
        val x = 6
        fun delayed(): Int = read()
        println(delayed())
        println(x)
    }
}

inline fun invokeLocal(block: () -> Int): Int { block(); return 99 }
fun ordinaryReturn(): Int {
    val result = invokeLocal(fun(): Int { return 5 })
    return result
}
fun counter(): () -> Int {
    var count = 0
    return fun(): Int { count++; return count }
}
fun retained(): () -> Int {
    val value = 7
    fun local(): Int = value
    return ::local
}
fun nestedReference(): () -> (() -> Int) {
    val value = 8
    fun local(): Int = value
    return { ::local }
}
interface ReadValue { fun value(): Int }
fun escapedObject(): ReadValue {
    val value = 30
    fun local(): Int = value
    return object: ReadValue { override fun value(): Int = local() }
}
class Owner(val base: Int) {
    fun create(): () -> Int {
        val extra = 2
        return fun(): Int { return base + extra }
    }
}
fun main() {
    lambdaShadow(); objectShadow(); localChainShadow()
    val triple = fun(x: Int): Int { if (x < 0) return 0; return x * 3 }
    println(triple(2)); println(triple(-2))
    val offset = 10
    val captured = fun(x: Int): Int = x + offset
    println(captured(5))
    val receiver = fun Int.(): String { return "OK" }
    println(1.receiver())
    println(ordinaryReturn())
    var shared = 0
    val increment = fun(): Int { shared++; return shared }
    val addTen = fun(): Int { shared += 10; return shared }
    println(increment()); println(addTen()); println(increment()); println(shared)
    val escaped = counter()
    println(escaped()); println(escaped())
    fun factorial(n: Int): Int { if (n < 2) return 1; return n * factorial(n - 1) }
    println(factorial(5))
    val initial = 2
    fun sum(n: Int): Int = if (n == 0) initial else n + sum(n - 1)
    println(sum(3))
    println(retained()())
    println(nestedReference()()())
    println(Owner(20).create()())
    println(escapedObject().value())
    fun <T> same(value: T): T = value
    println(same(13))
    val typed: (String) -> String = ::same
    println(typed("same"))
    var seed = 4
    fun defaulted(value: Int = seed): Int = value + 1
    println(defaulted()); seed = 8; println(defaulted()); println(defaulted(9))
    fun pick(value: Int): String = "int"
    fun pick(value: String): String = "string"
    println(pick(1)); println(pick("one"))
    val throughLambda = { sum(2) }
    println(throughLambda())
    println(listOf(1, 2, 3).map(fun(x: Int): Int { return x * x }))
}
