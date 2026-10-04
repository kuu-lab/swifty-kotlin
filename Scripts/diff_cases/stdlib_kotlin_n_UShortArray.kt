fun main() {
    try {
        UShortArray(-1)
        println("no throw")
    } catch (e: NegativeArraySizeException) {
        println("negative: ${e.message}")
    }

    val empty = UShortArray(0)
    val zeros = UShortArray(3)
    val values = UShortArray(4) { (it + 1).toUShort() }
    val storage = shortArrayOf(1, -1)
    val unsignedView = storage.asUShortArray()
    val signedView = unsignedView.asShortArray()
    storage[0] = -2
    println(empty.size)
    println(zeros[0])
    println(values[3].toInt())
    println(signedView[0])
    println(signedView[1])
}
