private let abi = RuntimeABISectionBuilder("Char")

public extension RuntimeABISpec {
    static let charFunctions: [RuntimeABIFunctionSpec] = [
        abi.th("__kk_char_rangeTo", "startValue endValue"),
        abi.nt("kk_char_compareTo", "lhsRaw rhsRaw"),
        abi.th("__kk_char_unicode_category", "code"),
        abi.th("__kk_char_is_uppercase", "code"),
        abi.th("__kk_char_is_lowercase", "code"),
    ]
}
