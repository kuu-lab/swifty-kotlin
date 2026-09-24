package golden.sema

fun configureHexFormatBuilder(builder: kotlin.text.HexFormat.Builder): kotlin.text.HexFormat {
    val bytesBuilder: kotlin.text.HexFormat.BytesHexFormat.Builder = builder.bytes
    val numberBuilder: kotlin.text.HexFormat.NumberHexFormat.Builder = builder.number
    val upperCase: Boolean = builder.upperCase
    bytesBuilder.byteSeparator = if (upperCase) ":" else "-"
    numberBuilder.prefix = if (upperCase) "0x" else "0X"
    builder.upperCase = true
    builder.bytes { byteSeparator = ":" }
    builder.number { prefix = "0x" }
    return builder.build()
}
