private let abi = RuntimeABISectionBuilder("String")

/// `__kk_string_toInt`/`toInt_radix`/`toIntOrNull`/`toIntOrNull_radix`/`toUByteOrNull`/
/// `toUShortOrNull`/`toUIntOrNull`/`toULongOrNull` (and their `_radix` variants)/`toDouble`/
/// `toDoubleOrNull`/`toLong`/`toLongOrNull`/`toFloat`/`toFloatOrNull`/`__kk_bignum_toString`
/// are already registered in `RuntimeABISpec+String.swift` (`stringFunctions`); they are
/// intentionally omitted here to avoid duplicate `allFunctions` entries.
public extension RuntimeABISpec {
    static let stringParsingFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_string_toShortOrNull", "strRaw"),
        abi.nt("__kk_string_toByteOrNull", "strRaw"),
        abi.th("__kk_string_toBigDecimal", "strRaw outThrown"),
        abi.th("__kk_string_toBigDecimalOrNull", "strRaw"),
        abi.th("__kk_double_toBigDecimal", "value outThrown"),
        abi.th("__kk_int_toBigDecimal", "valueRaw outThrown"),
        abi.th("__kk_long_toBigDecimal", "valueRaw outThrown"),
    ]
}
