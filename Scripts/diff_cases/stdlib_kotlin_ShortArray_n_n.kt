fun main() {
    val sizeOnly = ShortArray(3)
    println(sizeOnly.size)
    println(sizeOnly[0])
    println(sizeOnly[2])

    val values = ShortArray(4) { index ->
        when (index) {
            0 -> (-32768).toShort()
            1 -> (-1).toShort()
            2 -> 0.toShort()
            else -> 32767.toShort()
        }
    }
    println(values.size)
    println(values[0])
    println(values[1])
    println(values[2])
    println(values[3])

    println(ShortArray(0) { 42.toShort() }.size)

    try {
        ShortArray(-1)
        println("no throw")
    } catch (e: NegativeArraySizeException) {
        println("negative-size=${e.message}")
    }

    try {
        ShortArray(-2) { it.toShort() }
        println("no throw")
    } catch (e: NegativeArraySizeException) {
        println("negative-init-size=${e.message}")
    }
}
