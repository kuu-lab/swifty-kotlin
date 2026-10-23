fun main() {
    println("ff".toInt(16))
    println(42.toString(16))
    println(255.toString(2))
    println("-ff".toLong(16))
    println("7f".toByte(16))
    println("7fff".toShort(16))
    println(255u.toString(16))
    println(255uL.toString(16))
    println(255u.toUByte().toString(2))
    println(255u.toUShort().toString(16))
    println('A'.toDouble())
    println('A'.toFloat())
}
