import kotlinx.io.bytestring.*

fun main() {
    println(buildByteString { append(1, 2, 3); append(42U) }.toHexString())
    val builder = ByteStringBuilder()
    with(builder) {
        append(0x80U)
        append(byteArrayOf(4, 5), endIndex = 1)
    }
    println(builder.toByteString().toHexString())
    println(buildByteString {
        append(-128)
        append(255U)
        append(-1, 127)
    }.toHexString())
}
