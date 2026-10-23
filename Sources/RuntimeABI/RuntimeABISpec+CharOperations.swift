private let abi = RuntimeABISectionBuilder("Char")

public extension RuntimeABISpec {
    static let charFunctions: [RuntimeABIFunctionSpec] = [
        abi.th("__kk_char_rangeTo", "startValue endValue"),
        abi.nt("kk_char_compareTo", "lhsRaw rhsRaw"),
        // KSP-661: Char 判定系の Kotlin 化に伴い残す Unicode テーブル参照ブリッジ。
        abi.th("__kk_char_unicode_category", "code"),
        abi.th("__kk_char_is_uppercase", "code"),
        abi.th("__kk_char_is_lowercase", "code"),
    ]
}
