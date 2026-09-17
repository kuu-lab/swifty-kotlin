import kotlin.text.HexFormat

fun describeNumberHexFormatBuilder(builder: kotlin.text.HexFormat.NumberHexFormat.Builder): Boolean =
    builder.minLength > 0 && builder.prefix.isEmpty() && !builder.removeLeadingZeros && builder.suffix.isEmpty()

fun main() {
    println(HexFormat.Default.number.minLength > 0)
}
