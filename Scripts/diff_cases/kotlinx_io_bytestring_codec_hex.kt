import kotlinx.io.bytestring.ByteString
import kotlinx.io.bytestring.hexToByteString
import kotlinx.io.bytestring.toHexString
import kotlin.text.HexFormat

@OptIn(ExperimentalStdlibApi::class)
fun main() {
    val value = ByteString(byteArrayOf(-85, 18, -51, -17))
    println(value.toHexString())
    println(value.toHexString(HexFormat.UpperCase))
    println(value.toHexString(1, 3))
    println("ab12".hexToByteString().toHexString())
    println("".hexToByteString().size)
    try {
        "xz".hexToByteString()
    } catch (e: IllegalArgumentException) {
        println("hexToByteString-invalid-char")
    }
    try {
        "abc".hexToByteString()
    } catch (e: IllegalArgumentException) {
        println("hexToByteString-odd-length")
    }
}
