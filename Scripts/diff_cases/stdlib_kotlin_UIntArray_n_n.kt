@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    val empty = UIntArray(0)
    println("empty=${empty.size}")

    val zeroInitialized = UIntArray(3)
    println("zero=${zeroInitialized.joinToString()}")

    try {
        UIntArray(-1)
        println("negative=NO_THROW")
    } catch (e: NegativeArraySizeException) {
        println("negative=NegativeArraySizeException")
    }

    val signed = intArrayOf(1, 0, 42)
    val view = signed.asUIntArray()
    println("view=${view.joinToString()}")
    signed[1] = 99
    println("viewAfterWrite=${view[1]}")
}
