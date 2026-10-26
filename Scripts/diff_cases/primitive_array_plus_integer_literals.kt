fun main() {
    println((byteArrayOf(1) + 2).contentToString())
    println((shortArrayOf(7) + 2).contentToString())
    println((byteArrayOf(1) + listOf(2.toByte(), 3.toByte())).contentToString())
    println((shortArrayOf(7) + listOf(2.toShort(), 3.toShort())).contentToString())
}
