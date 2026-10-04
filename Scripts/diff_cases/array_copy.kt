@OptIn(kotlin.ExperimentalStdlibApi::class)
fun main() {
    // Basic array operations
    val arr = arrayOf(1, 2, 3, 4, 5)
    println(arr.size)
    println(arr[0])
    println(arr[4])

    // Array modification
    arr[0] = 99
    println(arr[0])

    // IntArray operations
    val intArr = intArrayOf(10, 20, 30)
    println(intArr.size)
    println(intArr[1])

    // Array element access and size
    val nums = arrayOf(100, 200, 300)
    println(nums.size)
    println(nums[2])

    // Array copy contract: truncation, null padding, and indexed initialization
    println(arr.copyOf(3).toList())
    println(arr.copyOf(7).toList())
    println(arr.copyOf(7) { index -> index * 10 }.toList())
    println(arr.copyOfRange(1, 4).toList())

    // copyInto must snapshot overlapping ranges before writing the destination
    val overlap = intArrayOf(1, 2, 3, 4)
    overlap.copyInto(overlap, destinationOffset = 1, startIndex = 0, endIndex = 3)
    println(overlap.toList())

    try {
        arr.copyOf(-1)
        println("no-throw")
    } catch (e: Throwable) {
        println("copyOf-negative")
    }
    try {
        arr.copyOfRange(4, 2)
        println("no-throw")
    } catch (e: Throwable) {
        println("copyOfRange-reversed")
    }
    try {
        arr.copyInto(arrayOf(0, 0), startIndex = 0, endIndex = arr.size)
        println("no-throw")
    } catch (e: Throwable) {
        println("copyInto-destination-too-small")
    }
}
