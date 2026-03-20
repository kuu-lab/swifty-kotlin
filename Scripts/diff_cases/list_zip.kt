fun main() {
    // Basic zip
    val a = listOf(1, 2, 3)
    val b = listOf("a", "b", "c")
    println(a.zip(b))

    // Zip with transform
    val nums = listOf(1, 2, 3)
    val strs = listOf("one", "two", "three")
    val result = nums.zip(strs) { n, s -> "$n=$s" }
    println(result)

    // Different lengths (shorter truncates)
    val short = listOf(1, 2)
    val long = listOf("x", "y", "z", "w")
    println(short.zip(long))
    println(long.zip(short))

    // Empty list zip
    val empty = listOf<Int>()
    println(empty.zip(listOf("a", "b")))
    println(listOf("a", "b").zip(empty))
    println(empty.zip(listOf<String>()))

    // Zip with transform and different lengths
    val left = listOf(10, 20, 30, 40)
    val right = listOf(1, 2)
    println(left.zip(right) { a, b -> a + b })

    // Pair access
    val pairs = listOf(1, 2, 3).zip(listOf("a", "b", "c"))
    for (p in pairs) {
        println("${p.first} -> ${p.second}")
    }
}
