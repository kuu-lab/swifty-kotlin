package golden.sema

fun hexFormatUpperCase(format: kotlin.text.HexFormat): Boolean = format.upperCase

fun hexFormatBytes(format: kotlin.text.HexFormat): kotlin.text.HexFormat.BytesHexFormat = format.bytes

fun hexFormatNumber(format: kotlin.text.HexFormat): kotlin.text.HexFormat.NumberHexFormat = format.number

fun hexFormatString(format: kotlin.text.HexFormat): String = format.toString()
