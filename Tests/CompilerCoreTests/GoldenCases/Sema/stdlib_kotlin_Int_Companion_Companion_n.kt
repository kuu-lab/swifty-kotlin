package golden.sema

fun main() {
    val directMax = Int.MAX_VALUE
    val directMin = Int.MIN_VALUE
    val directBits = Int.SIZE_BITS
    val directBytes = Int.SIZE_BYTES
    val receiverMax = Int.Companion.MAX_VALUE
    val receiverMin = Int.Companion.MIN_VALUE
    val receiverBits = Int.Companion.SIZE_BITS
    val receiverBytes = Int.Companion.SIZE_BYTES
    println(directMax)
    println(directMin)
    println(directBits)
    println(directBytes)
    println(receiverMax)
    println(receiverMin)
    println(receiverBits)
    println(receiverBytes)
}
