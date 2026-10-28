private let abi = RuntimeABISectionBuilder("Comparator")

public extension RuntimeABISpec {
    static let comparatorFunctions: [RuntimeABIFunctionSpec] = [
        abi.th("__kk_compare_with_comparator", "comparator a b outThrown"),
        abi.th("__kk_comparable_compareTo", "lhsRaw rhsRaw outThrown"),
        // `String.CASE_INSENSITIVE_ORDER` stays runtime backed: it is a companion
        // `val`, so every read has to observe the same comparator instance
        // (BUG-036/BUG-154), which the runtime singleton guarantees.
        abi.th("kk_string_case_insensitive_order_trampoline", "closureRaw a b outThrown"),
        abi.th("__kk_string_case_insensitive_order"),
        abi.nt("kk_primitive_compareTo", "lhsRaw rhsRaw kindRaw:int32"),
    ]
}
