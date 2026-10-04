import kotlin.text.HexFormat

fun acceptBytesHexFormatBuilder(
    builder: kotlin.text.HexFormat.BytesHexFormat.Builder?,
): Boolean = builder == null

fun main() {
    println(acceptBytesHexFormatBuilder(null))
}
