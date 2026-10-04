import kotlin.text.HexFormat

fun acceptNumberHexFormatBuilder(
    builder: kotlin.text.HexFormat.NumberHexFormat.Builder?,
): Boolean = builder == null

fun main() {
    println(acceptNumberHexFormatBuilder(null))
}
