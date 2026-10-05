fun <T> explicitFirst(values: List<T>): T = values.get(0)

fun shortFirst(values: List<Short>): Short = values.get(index = 0)

fun main() {
    val shorts = listOf(0xF0.toShort(), (-1).toShort())
    println(shorts.get(0))
    println(shorts[0])
    println(shortFirst(shorts))
    println(shorts.get(1).toInt())

    val bytes = listOf(0x55.toByte(), (-1).toByte())
    val byte: Byte = bytes.get(0)
    println(byte)
    println(bytes[0])
    println(bytes.get(0).toInt())
    println(bytes.get(1).toInt())
    println(listOf(0x55).get(0).countOneBits())

    println(listOf(1234567890123L).get(0))
    println(listOf(1.5f).get(0))
    println(listOf(2.5).get(0))
    println(listOf(true).get(0))
    println(listOf('K').get(0))

    println(explicitFirst(listOf("hello")))
    val mutable = mutableListOf("before")
    mutable[0] = "after"
    println(mutable.get(index = 0))
    println(explicitFirst(mutable))

    val nullableElements: List<String?> = listOf(null, "present")
    println(nullableElements.get(0))
    println(nullableElements.get(1)?.length)
    val absent: List<Short>? = null
    val present: List<Short>? = shorts
    println(absent?.get(0))
    println(present?.get(0))

    val nested = listOf(listOf(10, 20), listOf(30))
    println(nested.get(0).get(1))
    println(nested[0][1])
    try {
        shorts.get(-1)
    } catch (e: IndexOutOfBoundsException) {
        println("negative index")
    }
    try {
        shorts.get(shorts.size)
    } catch (e: IndexOutOfBoundsException) {
        println("end index")
    }
}
