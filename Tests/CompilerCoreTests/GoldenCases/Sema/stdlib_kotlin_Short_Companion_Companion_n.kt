package golden.sema

fun main() {
    val directMax: Short = Short.MAX_VALUE
    val directMin: Short = Short.MIN_VALUE
    val directBits: Int = Short.SIZE_BITS
    val directBytes: Int = Short.SIZE_BYTES
    val receiverMax: Short = Short.Companion.MAX_VALUE
    val receiverMin: Short = Short.Companion.MIN_VALUE
    val receiverBits: Int = Short.Companion.SIZE_BITS
    val receiverBytes: Int = Short.Companion.SIZE_BYTES
    val boxedMax: Any = Short.MAX_VALUE
    val boxedMin: Any = Short.MIN_VALUE
    println(directMax)
    println(directMin)
    println(directBits)
    println(directBytes)
    println(receiverMax)
    println(receiverMin)
    println(receiverBits)
    println(receiverBytes)
    println(boxedMax)
    println(boxedMin)
}
