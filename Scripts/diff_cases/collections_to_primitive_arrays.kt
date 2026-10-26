fun main() {
    println(listOf(true, false).toBooleanArray().contentToString())
    println(listOf(1.toByte(), 2.toByte()).toByteArray().contentToString())
    println(listOf('a', 'b').toCharArray().contentToString())
    println(listOf(1.5, 2.5).toDoubleArray().contentToString())
    println(listOf(1.0f, 2.0f).toFloatArray().contentToString())
    println(listOf(1, 2).toIntArray().contentToString())
    println(listOf(1L, 2L).toLongArray().contentToString())
    println(listOf(1.toShort(), 2.toShort()).toShortArray().contentToString())

    println(arrayOf(true, false).toBooleanArray().contentToString())
    println(arrayOf(1.toByte(), 2.toByte()).toByteArray().contentToString())
    println(arrayOf('a', 'b').toCharArray().contentToString())
    println(arrayOf(1.5, 2.5).toDoubleArray().contentToString())
    println(arrayOf(1.0f, 2.0f).toFloatArray().contentToString())
    println(arrayOf(1, 2).toIntArray().contentToString())
    println(arrayOf(1L, 2L).toLongArray().contentToString())
    println(arrayOf(1.toShort(), 2.toShort()).toShortArray().contentToString())
}
