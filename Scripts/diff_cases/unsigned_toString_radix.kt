fun main() {
    println(0u.toString(2))
    println(0uL.toString(36))
    println(255uL.toString(16))
    println(255u.toString(16))
    println(UInt.MAX_VALUE.toString(16))
    println(9223372036854775808uL.toString(16))
    println(ULong.MAX_VALUE.toString(2))
    println(255.toUByte().toString(2))
    println(255.toUShort().toString(8))
    println(65535.toUShort().toString(36))

    try {
        println(1u.toString(1))
    } catch (e: IllegalArgumentException) {
        println("invalid")
    }
    try {
        println(1uL.toString(37))
    } catch (e: IllegalArgumentException) {
        println("invalid")
    }
    try {
        println(1.toUByte().toString(0))
    } catch (e: IllegalArgumentException) {
        println("invalid")
    }
    try {
        println(1.toUShort().toString(1))
    } catch (e: IllegalArgumentException) {
        println("invalid")
    }
}
