// KUU-3505: Member-extension get/set operators in a with receiver must resolve
// for indexed postfix increment and preserve the old expression value.
object ExtProvider {
    var reads = 0
    var writes = 0
    var lastValue = 0L

    operator fun Long.get(i: Int): Long {
        reads++
        return this
    }

    operator fun Long.set(i: Int, newValue: Long) {
        writes++
        lastValue = newValue
    }
}

fun main() {
    with(ExtProvider) {
        var x = 0L
        val old = x[0]++
        println("$old:$x:$reads:$writes:$lastValue")
    }
}
