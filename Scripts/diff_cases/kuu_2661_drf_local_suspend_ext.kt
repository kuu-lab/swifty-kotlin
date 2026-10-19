val a = DeepRecursiveFunction<Int, Int> { n ->
    suspend fun DeepRecursiveScope<Int, Int>.b(): Int = 7
    suspend fun DeepRecursiveScope<Int, Int>.c(): Int = callRecursive(n - 1)
    if (n <= 0) b() else c()
}

fun main() {
    println(a(0))
    println(a(3))
}
