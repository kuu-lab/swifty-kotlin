// BUG-198: the hot built-in signed range loop must keep KSP-452 iteration
// semantics while avoiding the generic iterator dispatch in the lowered loop.
fun main() {
    var total = 0L
    for (i in 1..1000000) {
        total += i
    }
    println(total)

    val typed: IntRange = 1..5
    var typedCount = 0
    for (i in typed) {
        typedCount += i
    }
    println(typedCount)

    var steppedCount = 0
    for (i in 10 downTo 1 step 3) {
        steppedCount += i
    }
    println(steppedCount)
}
