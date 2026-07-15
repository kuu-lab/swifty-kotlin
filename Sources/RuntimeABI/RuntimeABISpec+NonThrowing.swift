public extension RuntimeABISpec {
    /// Runtime callee names emitted by the compiler that are not yet declared in
    /// `RuntimeABISpec.allFunctions` (RF-KIR-005 / RF-RT-005 follow-up).
    ///
    /// These are treated as non-throwing alongside spec-derived names until the
    /// symbols are added to the ABI spec.
    static let compilerInternalNonThrowingCalleeNames: Set<String> = [
        "kk_for_lowered",
        "kk_int_narrow",
        "kk_lambda_invoke",
        "kk_op_add",
        "kk_op_dmul",
        "kk_op_ishl",
        "kk_op_ishr",
        "kk_op_iushr",
        "kk_op_lshl",
        "kk_op_lshr",
        "kk_op_lushr",
        "kk_op_mul",
        "kk_op_sub",
        "kk_op_uge",
        "kk_op_ugt",
        "kk_op_ule",
        "kk_op_ult",
        "kk_op_uminus",
        "kk_op_uplus",
        "kk_uint_narrow",
    ]

    /// All runtime callee symbol names that do not use the `outThrown` ABI lowering path.
    static var nonThrowingRuntimeCalleeNames: Set<String> {
        let fromSpec = Set(allFunctions.lazy.filter { !$0.isThrowing }.map(\.name))
        return fromSpec.union(compilerInternalNonThrowingCalleeNames)
    }
}
