// DIFF_JVM
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

    var mutualEven: DeepRecursiveFunction<Int, Int>? = null
    var mutualOdd: DeepRecursiveFunction<Int, Int>? = null
    mutualEven = DeepRecursiveFunction { n ->
        when {
            n == 0 -> throw IllegalStateException("terminal")
            n == 4000 -> try {
                mutualOdd!!.callRecursive(n - 1)
            } catch (e: IllegalStateException) {
                7000
            }
            else -> mutualOdd!!.callRecursive(n - 1) + 1
        }
    }
    mutualOdd = DeepRecursiveFunction { n ->
        if (n == 0) throw IllegalStateException("terminal")
        else mutualEven!!.callRecursive(n - 1) + 1
    }
    println(mutualEven!!(10000))
}
