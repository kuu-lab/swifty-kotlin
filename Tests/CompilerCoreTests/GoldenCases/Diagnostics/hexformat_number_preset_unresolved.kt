// KUU-1390: `HexFormat.Number` is not a real Kotlin stdlib API. Upstream
// kotlin.text.HexFormat (1.9 through current) exposes only the `Default` and
// `UpperCase` companion presets, and kotlinc reports `unresolved reference
// 'Number'` for it. The intended "0x"-prefixed number format is spelled
// `HexFormat { number.prefix = "0x" }`. This case pins the SEMA-0024 rejection
// so the nonexistent preset is not accidentally added as a KSwiftK-only
// extension that real Kotlin would reject.
fun main() {
    // Valid companion presets and the DSL equivalent must keep resolving
    // (any diagnostic on these lines would fail the golden).
    println(255.toHexString(HexFormat.Default))
    println(255.toHexString(HexFormat.UpperCase))
    println(255.toHexString(HexFormat { number.prefix = "0x" }))

    // ERROR: HexFormat.Number does not exist in upstream Kotlin — KSWIFTK-SEMA-0024
    println(255.toHexString(HexFormat.Number))
    println("0xff".hexToInt(HexFormat.Number))
}
