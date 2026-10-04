import kotlin.text.HexFormat

fun acceptHexFormatNestedTypes(
    builder: kotlin.text.HexFormat.Builder?,
    bytes: kotlin.text.HexFormat.BytesHexFormat?,
    companion: kotlin.text.HexFormat.Companion?,
    number: kotlin.text.HexFormat.NumberHexFormat?,
): Boolean = builder == null && bytes == null && companion == null && number == null

fun main() {
    println(acceptHexFormatNestedTypes(null, null, null, null))
}
