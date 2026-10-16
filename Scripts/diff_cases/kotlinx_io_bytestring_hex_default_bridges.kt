import kotlinx.io.bytestring.ByteString
import kotlinx.io.bytestring.hexToByteString
import kotlinx.io.bytestring.toHexString

fun main() {
    val value = ByteString(byteArrayOf(-85, 18, -51, -17))
    println(value.toHexString())
    println(value.toHexString(1))
    println(value.toHexString(endIndex = 2))
    println(value.toHexString(1, 3))
    println(value.toHexString(startIndex = 1, endIndex = 3))

    println(ByteString(byteArrayOf()).toHexString())
    println("".hexToByteString().size)
    println("ab12".hexToByteString().toHexString())

    try {
        value.toHexString(3, 1)
    } catch (error: IllegalArgumentException) {
        println("hex-range-invalid-order")
    }
    try {
        "ab cd".hexToByteString()
    } catch (error: IllegalArgumentException) {
        println("hex-default-rejects-separator")
    }
}
