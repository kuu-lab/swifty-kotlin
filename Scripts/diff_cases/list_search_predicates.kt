fun main() {
    val nums = listOf(2, 4, 3, 4, 5)

    // count / any / all / none
    println(nums.count())
    println(nums.count { it > 3 })
    println(nums.any { it > 4 })
    println(nums.all { it > 0 })
    println(nums.none { it > 10 })

    // find / findLast
    println(nums.find { it > 3 })
    println(nums.findLast { it > 3 })
    println(nums.firstOrNull { it > 4 })
    println(nums.lastOrNull { it > 4 })

    // indexOf / lastIndexOf / contains
    println(nums.indexOf(4))
    println(nums.lastIndexOf(4))
    println(nums.contains(3))
    println(nums.containsAll(listOf(2, 3)))
    println(nums.containsAll(listOf(2, 6)))

    // indexOfFirst / indexOfLast
    println(nums.indexOfFirst { it % 2 == 1 })
    println(nums.indexOfLast { it % 2 == 0 })

    // in / !in
    println(3 in nums)
    println(6 in nums)
    println(6 !in nums)
}
