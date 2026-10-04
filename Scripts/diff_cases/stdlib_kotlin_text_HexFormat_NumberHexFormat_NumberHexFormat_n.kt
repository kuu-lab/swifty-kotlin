import kotlin.text.HexFormat

fun describeNumberHexFormat(format: kotlin.text.HexFormat.NumberHexFormat): String =
    format.prefix + format.suffix + format.removeLeadingZeros + format.minLength + format.toString()

fun main() {
    println(describeNumberHexFormat(HexFormat.Default.number).isNotEmpty())
}
