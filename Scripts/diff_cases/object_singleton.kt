object Counter {
    var n: Int = 0
    fun increment() { n = n + 1 }
}

fun main() {
    Counter.increment()
    Counter.increment()
    println(Counter.n)
    // Explicit-receiver assignment from outside the object must write the
    // same global slot `increment()`'s bare-name `n = ...` uses.
    Counter.n = Counter.n + 1
    println(Counter.n)
    Counter.n += 10
    println(Counter.n)
    Counter.n++
    println(Counter.n)
}
