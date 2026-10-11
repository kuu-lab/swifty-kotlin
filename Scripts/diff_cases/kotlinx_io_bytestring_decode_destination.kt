import kotlin.io.encoding.Base64
import kotlinx.io.bytestring.*

fun main() {
    try {
        Base64.decodeIntoByteArray(ByteString("AB==".encodeToByteArray()), ByteArray(0))
        println("accepted")
    } catch (failure: IndexOutOfBoundsException) {
        println("IOOB")
    } catch (failure: IllegalArgumentException) {
        println("IAE")
    }

    val destination = byteArrayOf(9, 9, 9, 9, 9, 9)
    try {
        Base64.decodeIntoByteArray(ByteString("AAAA!!!!".encodeToByteArray()), destination)
    } catch (failure: IllegalArgumentException) {
        println("invalid-symbol")
    }
    println(destination.toHexString())
    try {
        Base64.Mime.decodeToByteString("!")
    } catch (failure: IllegalArgumentException) {
        println("mime-single:IllegalArgumentException")
    }
    try {
        Base64.Pem.decodeToByteString("!")
    } catch (failure: IllegalArgumentException) {
        println("pem-single:IllegalArgumentException")
    }
    println("mime-double:" + Base64.Mime.decodeToByteString("!!").size)
    val hugeFormat = HexFormat { bytes { bytePrefix = "x".repeat(32768) } }
    try {
        ByteString(ByteArray(65536)).toHexString(hugeFormat)
    } catch (failure: IllegalArgumentException) {
        println("hex-length:IllegalArgumentException")
    }

}
