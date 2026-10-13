import kotlin.concurrent.getOrSet

class Value {
    fun reset(): String = "reset"
}

class ProtectedLocal : ThreadLocal<String>() {
    protected override fun initialValue(): String = "protected"
}

fun main() {
    var calls = 0
    val local: ThreadLocal<String> = object : ThreadLocal<String>() {
        override fun initialValue(): String {
            calls++
            return "value"
        }
    }
    println(local.get())
    println(local.get())
    println(local.getOrSet { "unused" })
    println(calls)
    println(ProtectedLocal().get())

    var nullCalls = 0
    val nullable = object : ThreadLocal<String>() {
        override fun initialValue(): String? {
            nullCalls++
            return null
        }
    }
    println(nullable.get())
    println(nullable.get())
    println(nullCalls)
    println(nullable.getOrSet { "fallback" })
    println(nullable.get())
    println(nullCalls)

    val direct = ThreadLocal<String>()
    println(direct.get())
    println(direct.getOrSet { "direct" })
    println(direct.getOrSet { "unused" })
    val ints = ThreadLocal<Int>()
    println(ints.getOrSet { 42 })
    println(ints.get())
    println(ints.getOrSet { 99 })
    val values = object : ThreadLocal<Value>() {
        override fun initialValue() = Value()
    }
    println(values.get().reset())
}
