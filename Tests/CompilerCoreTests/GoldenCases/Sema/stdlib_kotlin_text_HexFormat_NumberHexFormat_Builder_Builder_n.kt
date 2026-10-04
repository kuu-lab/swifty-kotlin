package golden.sema

fun configureNumberHexFormatBuilder(builder: kotlin.text.HexFormat.NumberHexFormat.Builder): Any? {
    builder.minLength = 4
    builder.prefix = "0x"
    builder.removeLeadingZeros = true
    builder.suffix = "h"
    return builder
}
