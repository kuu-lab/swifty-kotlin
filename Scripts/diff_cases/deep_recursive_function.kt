fun main() {
    val depth = DeepRecursiveFunction<Int, Int> { n ->
        if (n <= 0) 0 else callRecursive(n - 1) + 1
    }
    println(depth(1000))

    val triangular = DeepRecursiveFunction<Int, Int> {
        if (it <= 0) 0 else it + callRecursive(it - 1)
    }
    println(triangular(100))

    val limit = 3
    val clamped = DeepRecursiveFunction<Int, Int> { n ->
        if (n <= 0 || n > limit) n else callRecursive(n - 1) + 1
    }
    println(clamped(limit))
    println(clamped(10))
}
