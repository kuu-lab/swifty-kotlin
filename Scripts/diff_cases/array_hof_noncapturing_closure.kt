fun main() {
    val nums = arrayOf(1, 2, 3, 4, 5)

    println(nums.any { it > 4 })
    println(nums.any { it > 10 })
    println(nums.all { it > 0 })
    println(nums.all { it > 3 })
    println(nums.none { it < 0 })
    println(nums.none { it > 0 })
    println(nums.count { it % 2 == 0 })

    println(nums.map { it * 2 })
    println(nums.filter { it > 2 })
    nums.forEach { print(it) }
    println()
    println(nums.reduce { acc, value -> acc + value })
}
