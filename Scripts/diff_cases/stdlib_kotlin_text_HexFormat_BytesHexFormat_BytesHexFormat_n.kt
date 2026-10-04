import kotlin.text.HexFormat

fun describeBytesHexFormat(format: kotlin.text.HexFormat.BytesHexFormat): String =
    format.bytePrefix + format.byteSeparator + format.byteSuffix +
        format.bytesPerGroup + format.bytesPerLine + format.groupSeparator + format.toString()

fun main() {
    println(describeBytesHexFormat(HexFormat.Default.bytes).isNotEmpty())
}
