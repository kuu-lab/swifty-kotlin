package golden.sema

fun numberHexFormatProperties(format: kotlin.text.HexFormat.NumberHexFormat): String {
    val values = format.prefix + format.suffix + format.removeLeadingZeros.toString()
    return values + format.minLength + format.toString()
}
