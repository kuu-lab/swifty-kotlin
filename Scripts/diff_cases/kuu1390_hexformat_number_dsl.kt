// KUU-1390: upstream Kotlin has no `HexFormat.Number` companion preset; the
// supported spelling for a "0x"-prefixed number format is the `number` DSL
// (`HexFormat { number.prefix = "0x" }`). This case pins JVM parity for that
// path — the exact output the missing-preset report was after ("0x000000ff").
fun main() {
    val numberFormat = HexFormat { number.prefix = "0x" }

    // Int.toHexString keeps full 8-digit padding after the "0x" prefix.
    println(255.toHexString(numberFormat))          // 0x000000ff
    println(0.toHexString(numberFormat))            // 0x00000000
    println((-1).toHexString(numberFormat))         // 0xffffffff

    // Long.toHexString keeps full 16-digit padding.
    println(255L.toHexString(numberFormat))         // 0x00000000000000ff

    // Parsing strips the required "0x" prefix (case-insensitive).
    println("0xff".hexToInt(numberFormat))          // 255
    println("0XFF".hexToInt(numberFormat))          // 255
    println("0x000000ff".hexToInt(numberFormat))    // 255
    println("0xffffffffffffffff".hexToLong(numberFormat))  // -1
}
