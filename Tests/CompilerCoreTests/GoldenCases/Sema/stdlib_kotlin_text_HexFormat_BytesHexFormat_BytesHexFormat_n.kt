package golden.sema

fun bytesHexFormatProperties(format: kotlin.text.HexFormat.BytesHexFormat): String {
    val values = format.bytePrefix + format.byteSeparator + format.byteSuffix
    val sizes = format.bytesPerGroup + format.bytesPerLine
    return values + format.groupSeparator + sizes.toString() + format.toString()
}
