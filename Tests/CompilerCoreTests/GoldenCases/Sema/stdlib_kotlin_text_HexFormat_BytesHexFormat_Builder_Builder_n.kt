package golden.sema

fun configureBytesHexFormatBuilder(builder: kotlin.text.HexFormat.BytesHexFormat.Builder): Any? {
    builder.bytePrefix = "0x"
    builder.byteSeparator = ":"
    builder.byteSuffix = "h"
    builder.bytesPerGroup = 2
    builder.bytesPerLine = 8
    builder.groupSeparator = "|"
    return builder
}
