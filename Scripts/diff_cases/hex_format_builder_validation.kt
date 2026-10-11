private fun escaped(value: String): String = value.replace("\r", "\\r").replace("\n", "\\n")

private fun getInt(builder: HexFormat.BytesHexFormat.Builder, name: String): Int =
    if (name == "bytesPerLine") builder.bytesPerLine else builder.bytesPerGroup

private fun setInt(builder: HexFormat.BytesHexFormat.Builder, name: String, value: Int) {
    if (name == "bytesPerLine") builder.bytesPerLine = value else builder.bytesPerGroup = value
}

private fun rejectInt(builder: HexFormat.BytesHexFormat.Builder, name: String, value: Int) {
    val previous = getInt(builder, name)
    var rejected = false
    try {
        setInt(builder, name, value)
    } catch (failure: IllegalArgumentException) {
        rejected = true
        check(failure.message == "Non-positive values are prohibited for $name, but was $value")
    }
    check(rejected)
    check(getInt(builder, name) == previous)
    println("$name=$value|IllegalArgumentException|unchanged")
}

private fun getToken(builder: HexFormat.BytesHexFormat.Builder, name: String): String = when (name) {
    "byteSeparator" -> builder.byteSeparator
    "bytePrefix" -> builder.bytePrefix
    else -> builder.byteSuffix
}

private fun setToken(builder: HexFormat.BytesHexFormat.Builder, name: String, value: String) {
    when (name) {
        "byteSeparator" -> builder.byteSeparator = value
        "bytePrefix" -> builder.bytePrefix = value
        else -> builder.byteSuffix = value
    }
}

private fun rejectToken(builder: HexFormat.BytesHexFormat.Builder, name: String, value: String) {
    val previous = getToken(builder, name)
    var rejected = false
    try {
        setToken(builder, name, value)
    } catch (failure: IllegalArgumentException) {
        rejected = true
        check(failure.message == "LF and CR characters are prohibited in $name, but was $value")
    }
    check(rejected)
    check(getToken(builder, name) == previous)
    println("$name=${escaped(value)}|IllegalArgumentException|unchanged")
}

fun main() {
    val format = HexFormat {
        bytes {
            check(bytesPerLine == Int.MAX_VALUE && bytesPerGroup == Int.MAX_VALUE)
            check(groupSeparator == "  " && byteSeparator == "" && bytePrefix == "" && byteSuffix == "")
            println("defaults=ok")
            bytesPerLine = 1
            bytesPerGroup = 1
            bytesPerLine = Int.MAX_VALUE
            bytesPerGroup = Int.MAX_VALUE
            bytesPerLine = 5
            bytesPerGroup = 2
            println("positive=ok")

            // Explicit-receiver assignments in helpers complement bare-name DSL assignments.
            rejectInt(this, "bytesPerLine", 0)
            rejectInt(this, "bytesPerLine", -1)
            rejectInt(this, "bytesPerGroup", 0)
            rejectInt(this, "bytesPerGroup", -1)
            byteSeparator = ":"
            bytePrefix = "["
            byteSuffix = "]"
            for (name in arrayOf("byteSeparator", "bytePrefix", "byteSuffix")) {
                for (value in arrayOf("\r", "\n", "x\rY", "x\nY", "x\r\nY")) {
                    rejectToken(this, name, value)
                }
            }

            // Kotlin 2.3.10 deliberately has no CR/LF validation on this property.
            for (value in arrayOf("\r", "\n", "x\rY", "x\nY", "x\r\nY")) {
                groupSeparator = value
                check(groupSeparator == value)
                println("groupSeparator=${escaped(value)}|accepted")
            }
            groupSeparator = " | "
        }
    }
    check(format.bytes.bytesPerLine == 5 && format.bytes.bytesPerGroup == 2)
    check(format.bytes.byteSeparator == ":" && format.bytes.bytePrefix == "[" && format.bytes.byteSuffix == "]")
    val data = byteArrayOf(0, 1, 2, 3, 4, 5)
    val encoded = data.toHexString(format)
    check(encoded == "[00]:[01] | [02]:[03] | [04]\n[05]")
    check(encoded.hexToByteArray(format).contentEquals(data))
    check(encoded.replace("\n", "\r").hexToByteArray(format).contentEquals(data))
    check(encoded.replace("\n", "\r\n").hexToByteArray(format).contentEquals(data))
    println("grouped=${escaped(encoded)}|LF-CR-CRLF-roundtrip")

    val newlineGroups = HexFormat { bytes { bytesPerGroup = 2; groupSeparator = "\r\n" } }
    val withNewlineGroups = data.toHexString(newlineGroups)
    check(withNewlineGroups == "0001\r\n0203\r\n0405")
    check(withNewlineGroups.hexToByteArray(newlineGroups).contentEquals(data))
    println("newlineGroups=${escaped(withNewlineGroups)}|roundtrip")
}
