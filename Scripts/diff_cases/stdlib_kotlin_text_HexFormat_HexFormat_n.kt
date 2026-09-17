import kotlin.text.HexFormat

fun describeHexFormat(format: kotlin.text.HexFormat): String =
    format.upperCase.toString() + format.bytes.toString() + format.number.toString() + format.toString()

fun main() {
    println(describeHexFormat(HexFormat.UpperCase).isNotEmpty())
}
