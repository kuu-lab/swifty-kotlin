// KUU-3600: a prefix increment with an omitted extension-operator argument
// must call the default-argument stub even when no postfix increment precedes it.
class A
operator fun A.inc(s: String = "OK"): A = this

var defaultCalls = 0
fun defaultStep(): Int {
    defaultCalls += 1
    return 2
}

class Counter(val value: Int)
operator fun Counter.inc(step: Int = defaultStep()): Counter = Counter(value + step)
operator fun Counter.dec(step: Int = defaultStep()): Counter = Counter(value - step)

fun main() {
    var a = A()
    ++a
    println("OK")

    var counter = Counter(10)
    ++counter
    println("prefix statement: ${counter.value}, defaults=$defaultCalls")
    val prefix = ++counter
    println("prefix value: ${prefix.value}, current=${counter.value}, defaults=$defaultCalls")
    val postfix = counter++
    println("postfix value: ${postfix.value}, current=${counter.value}, defaults=$defaultCalls")
    val decrement = --counter
    println("prefix decrement: ${decrement.value}, current=${counter.value}, defaults=$defaultCalls")
    val postDecrement = counter--
    println("postfix decrement: ${postDecrement.value}, current=${counter.value}, defaults=$defaultCalls")
}
