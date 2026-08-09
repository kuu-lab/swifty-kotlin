// Regression: slots requested while lowering a loop body (the thrown-value slot
// of a call, string bridge scratch) used to be alloca'd inside the loop block,
// so the stack grew once per iteration and long loops crashed with SIGSEGV.
class Counter {
    var value: Int = 0
    fun bump(): Int {
        value += 1
        return value
    }
}

fun main() {
    val counter = Counter()
    var i = 0
    while (i < 2000000) {
        counter.bump()
        i += 1
    }
    println(counter.value)

    var total = 0
    var j = 0
    while (j < 200000) {
        total += "v$j".length
        j += 1
    }
    println(total)
}
