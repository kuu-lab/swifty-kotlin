// KSP-825 regression: function-valued factories need closure materialization,
// while ordinary runtime factories must keep their existing argument ordering.
fun main() {
    val recursive = DeepRecursiveFunction<Int, Int> { value ->
        if (value == 0) 0 else callRecursive(value - 1) + 1
    }
    println(recursive(3))
    println(listOf("a" to 1).toMap()["a"])
    try {
        ArrayDeque<Int>().first()
    } catch (e: NoSuchElementException) {
        println(e.message)
    }
}
