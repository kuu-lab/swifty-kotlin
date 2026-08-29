import kotlin.math.E

fun main() {
    val copied = E
    println(E.toRawBits() == 0x4005bf0a8b145769L)
    println(copied.toRawBits() == 0x4005bf0a8b145769L)
}
