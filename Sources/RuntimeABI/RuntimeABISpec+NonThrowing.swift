public extension RuntimeABISpec {
    static let compilerInternalNonThrowingCalleeNames: Set<String> = [
        "__kk_int_range_induction_add",
        "__kk_int_range_induction_le",
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

    static let compilerInternalBuiltinCalleeNames: Set<String> = [
        "__kk_string_struct_get_length",
        "kk_string_struct_get_length",
        "length",
    ]

    static let compilerGeneratedLinkNamePrefix = "kk_fn_"

    static var nonThrowingRuntimeCalleeNames: Set<String> {
        let fromSpec = Set(allFunctions.lazy.filter { !$0.isThrowing }.map(\.name))
        return fromSpec.union(compilerInternalNonThrowingCalleeNames)
    }
}
