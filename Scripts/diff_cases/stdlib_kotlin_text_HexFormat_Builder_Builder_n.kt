import kotlin.text.HexFormat

fun describeHexFormatBuilder(builder: kotlin.text.HexFormat.Builder): Boolean =
    builder.upperCase && builder.bytes.byteSeparator.isEmpty() && builder.number.prefix.isEmpty()

fun main() {
    println(HexFormat.Default.upperCase)
}
