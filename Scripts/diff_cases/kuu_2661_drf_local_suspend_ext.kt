val a = DeepRecursiveFunction<Int, Int> { n ->
    suspend fun DeepRecursiveScope<Int, Int>.b(): Int = 7
    b()
}

val a2 = DeepRecursiveFunction<Int, Int> { n ->
    suspend fun DeepRecursiveScope<Int, Int>.b(): Int = callRecursive(n - 1)
    if (n <= 0) 0 else b()
}

fun main() {
    println(a(0))
    println(a2(0))
}
