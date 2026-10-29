fun main() {
    println('a' to 'b')
    println(true to false)
    println(1.0f to 2.0f)
    println(1.0 to 2.0)
    println("ab".associate { it to 1 })
    println(charArrayOf('a').associate { it.toString() to it })
    println(booleanArrayOf(true).associate { it.toString() to it })
    println(floatArrayOf(1.0f).associate { it.toString() to it })
    val doubles: List<Double?> = listOf(null, -0.0, 1.5)
    println(doubles.map { it to 1 })
    val chars: List<Char?> = listOf(null, 'a')
    println(chars.map { it to 1 })
    val bytes = byteArrayOf(7).associate { it.toString() to it }
    println(bytes)
    println(bytes["7"] is Byte)
    val shorts = shortArrayOf(9).associate { it.toString() to it }
    println(shorts)
    println(shorts["9"] is Short)
}
