fun main() {
    // Integer-family joins stay unified: unsuffixed literals adopt the
    // widest member, so these are not intersections on the JVM either.
    val longs = arrayOf(1, 2L)
    println(longs.joinToString())
    println(longs.size)
    val ulongs = arrayOf(1u, 2uL)
    println(ulongs.joinToString())

    // An explicit type argument keeps a mixed builtin join legal.
    val explicit = arrayOf<Any?>("a", null, 1)
    println(explicit.joinToString())

    // An expected result type steers inference to the declared element type.
    val anyArr: Array<Any> = arrayOf("a", 1)
    println(anyArr.joinToString())

    // Non-reified generic inference may still produce an intersection.
    val mixed = listOf("a", 1)
    println(mixed.joinToString())
    val nums = listOf(1, 1.5)
    println(nums.joinToString())
    val n: Number = nums[0]
    println(n)
}
