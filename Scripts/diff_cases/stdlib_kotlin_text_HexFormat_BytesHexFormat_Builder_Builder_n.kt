import kotlin.text.HexFormat

fun describeBytesHexFormatBuilder(builder: kotlin.text.HexFormat.BytesHexFormat.Builder): Boolean =
    builder.bytesPerGroup > 0 && builder.bytesPerLine > 0 && builder.groupSeparator.isNotEmpty()

fun main() {
    println(HexFormat.Default.bytes.bytesPerGroup > 0)
}
