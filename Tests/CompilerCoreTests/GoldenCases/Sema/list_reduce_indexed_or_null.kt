fun main() {
    val nums = listOf(1, 2, 3, 4)
    val result: Int? = nums.reduceIndexedOrNull { index, acc, value -> acc + index * value }
    println(result)

    val empty = listOf<Int>()
    val nullResult: Int? = empty.reduceIndexedOrNull { index, acc, value -> acc + index * value }
    println(nullResult)
}
