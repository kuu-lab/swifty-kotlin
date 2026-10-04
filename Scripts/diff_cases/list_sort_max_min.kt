fun main() {
    val nums = listOf(3, 1, 4, 1, 5, 9, 2, 6)
    println(nums.sorted().toString())
    println(nums.sortedDescending().toString())
    println(nums.sortedBy { it }.toString())
    println(nums.sortedByDescending { it }.toString())
    println(nums.sortedWith { a, b -> a - b }.toString())
    println(nums.max().toString())
    println(nums.min().toString())
    println(nums.maxOrNull().toString())
    println(nums.minOrNull().toString())
    println(nums.maxBy { it }.toString())
    println(nums.minBy { it }.toString())
    println(nums.maxOf { it * 2 }.toString())
    println(nums.minOf { it }.toString())
    println(nums.maxWith { a, b -> a - b }.toString())
    println(nums.minWith { a, b -> a - b }.toString())
    println(nums.maxOfWith({ a, b -> a - b }, { it * 2 }).toString())
    println(nums.minOfWith({ a, b -> a - b }, { it }).toString())

    val mutable = mutableListOf(3, 1, 4, 1, 5)
    mutable.sort()
    println(mutable.toString())
    mutable.sortDescending()
    println(mutable.toString())
    mutable.sortBy { it }
    println(mutable.toString())
    mutable.sortByDescending { it }
    println(mutable.toString())
    mutable.sortWith { a, b -> a - b }
    println(mutable.toString())
}
