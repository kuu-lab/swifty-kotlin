// KUU-642: DeepRecursiveFunction trampoline + exception propagation.
fun main() {
    val sumTo = DeepRecursiveFunction<Int, Int> {
        if (it <= 0) 0 else it + callRecursive(it - 1)
    }
    println(sumTo(1000))

    val boom = DeepRecursiveFunction<Int, Int> { throw RuntimeException("boom") }
    try {
        boom(0)
    } catch (e: RuntimeException) {
        println("caught")
    }

    val step = 3
    val countDown = DeepRecursiveFunction<Int, Int> { n ->
        if (n <= 0) 0 else callRecursive(n - step) + 1
    }
    println(countDown(9))

    val identity = DeepRecursiveFunction<Int, Int> { it }
    val hop = DeepRecursiveFunction<Int, Int> { n ->
        if (n <= 0) 0 else identity.callRecursive(n - 1) + 1
    }
    println(hop(8))
}
