package golden.sema

fun main() {
    val values = ShortArray(4) { index ->
        when (index) {
            0 -> (-32768).toShort()
            1 -> (-1).toShort()
            2 -> 0.toShort()
            else -> 32767.toShort()
        }
    }
    println(values[0])
}
