@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

fun main() {
    val storage = byteArrayOf(1, -1)
    val values = UByteArray(storage)
    println(values.size)
    println(values[0])
    println(values[1])

    storage[0] = 7
    println(values[0])
    values[1] = 2.toUByte()
    println(storage[1])

    val empty = UByteArray(0)
    println(empty.size)
    val zeros = UByteArray(3)
    println(zeros[0])
    println(zeros[2])

    try {
        UByteArray(-1)
        println("no throw")
    } catch (e: NegativeArraySizeException) {
        println("negative")
    }
}
