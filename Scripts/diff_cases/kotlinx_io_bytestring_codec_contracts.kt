import kotlin.io.encoding.Base64
import kotlinx.io.bytestring.*

class ByteStringCodecSymbols : CharSequence {
    override val length: Int get() = 4
    override fun get(index: Int): Char = "AA=="[index]
    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        "AA==".substring(startIndex, endIndex)
    override fun toString(): String = "xxxx"
}

fun byteStringCodecFailure(name: String, action: () -> Unit) {
    try {
        action()
        println(name + ":accepted")
    } catch (failure: NumberFormatException) {
        println(name + ":NumberFormatException")
    } catch (failure: IndexOutOfBoundsException) {
        println(name + ":IndexOutOfBoundsException")
    } catch (failure: IllegalArgumentException) {
        println(name + ":IllegalArgumentException")
    }
}

fun main() {
    val source = ByteString(0, 1, 2)
    byteStringCodecFailure("encode-start") { Base64.encode(source, startIndex = 4) }
    byteStringCodecFailure("decode-string-start") { Base64.decodeToByteString("AA==", startIndex = 5) }
    byteStringCodecFailure("decode-array-start") { Base64.decodeToByteString("AA==".encodeToByteArray(), startIndex = 5) }
    byteStringCodecFailure("negative-before-reversed") { Base64.encode(source, -1, -2) }
    byteStringCodecFailure("outside-before-reversed") { Base64.encode(source, 5, 4) }
    byteStringCodecFailure("pad-bits-two") { Base64.decodeToByteString("AB==") }
    byteStringCodecFailure("pad-bits-three") { Base64.decodeToByteString("AAB=") }
    byteStringCodecFailure("pad-bits-absent") {
        Base64.withPadding(Base64.PaddingOption.ABSENT).decodeToByteString("AB")
    }
    println("zero-pad-bits:" + Base64.decodeToByteString("AAA=").toHexString())
    println("char-sequence:" + Base64.decodeToByteString(ByteStringCodecSymbols()).toHexString())

    val format = HexFormat {
        bytes {
            bytesPerLine = 3
            bytesPerGroup = 2
            byteSeparator = ":"
            groupSeparator = "|"
        }
    }
    val bytes = ByteString(0, 1, 2, 3, 4, 5, 6)
    println(bytes.toHexString(format))
    println(bytes.toHexString(1, 7, format))
    println("00:01|02\n03:04|05\n06".hexToByteString(format).toHexString())
    println("00:01|02\r\n03:04|05\r\n06".hexToByteString(format).toHexString())
    byteStringCodecFailure("fullwidth-digits") { "１２".hexToByteString() }
    byteStringCodecFailure("fullwidth-letters") { "ＡＢ".hexToByteString() }
    byteStringCodecFailure("fullwidth-number") { "１２".hexToInt() }
}
