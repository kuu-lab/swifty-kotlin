fun configureHexFormatBuilder(builder: kotlin.text.HexFormat.Builder): Boolean {
    val bytesBuilder = builder.bytes
    val numberBuilder = builder.number
    builder.upperCase = !builder.upperCase
    builder.bytes { byteSeparator = ":" }
    builder.number { prefix = "0x" }
    return builder.upperCase && bytesBuilder.byteSeparator.isNotEmpty() && numberBuilder.prefix.isNotEmpty()
}

@OptIn(kotlin.ExperimentalStdlibApi::class)
fun main() {
    println(kotlin.text.HexFormat.Default.upperCase)
}
