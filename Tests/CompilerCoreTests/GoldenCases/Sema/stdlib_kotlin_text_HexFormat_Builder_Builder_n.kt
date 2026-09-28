package golden.sema
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
fun configureHexFormatBuilder(builder: kotlin.text.HexFormat.Builder): kotlin.text.HexFormat {
    builder.upperCase = true
    builder.bytes { byteSeparator = ":" }
    builder.number { prefix = "0x" }
    return builder.build()
}
