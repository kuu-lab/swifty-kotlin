private let abi = RuntimeABISectionBuilder("Bitwise")

public extension RuntimeABISpec {
    static let opFloorDivSpec: RuntimeABIFunctionSpec = abi.th("kk_op_floor_div", "lhs rhs outThrown")
    static let opLfloorDivSpec: RuntimeABIFunctionSpec = abi.th("kk_op_lfloor_div", "lhs rhs outThrown")
    static let opFloorModSpec: RuntimeABIFunctionSpec = abi.th("kk_op_floor_mod", "lhs rhs outThrown")
    static let opLfloorModSpec: RuntimeABIFunctionSpec = abi.th("kk_op_lfloor_mod", "lhs rhs outThrown")

    static let bitwiseFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("kk_bitwise_and", "a b"),
        abi.nt("kk_bitwise_or", "a b"),
        abi.nt("kk_bitwise_xor", "a b"),
        abi.nt("kk_op_inv", "a"),
        abi.nt("kk_op_shl", "a b"),
        abi.nt("kk_op_shr", "a b"),
        abi.nt("kk_op_ushr", "a b"),
        abi.nt("kk_op_dmul", "a b"),
        abi.nt("kk_op_eq", "lhs rhs"),
        abi.th("kk_op_ne", "lhs rhs"),
        abi.th("kk_op_lt", "lhs rhs"),
        abi.th("kk_op_le", "lhs rhs"),
        abi.th("kk_op_gt", "lhs rhs"),
        abi.th("kk_op_ge", "lhs rhs"),
        abi.th("kk_op_ult", "lhs rhs"),
        abi.th("kk_op_ule", "lhs rhs"),
        abi.th("kk_op_ugt", "lhs rhs"),
        abi.th("kk_op_uge", "lhs rhs"),
        abi.th("kk_op_div", "lhs rhs outThrown"),
        opFloorDivSpec,
        opLfloorDivSpec,
        abi.th("kk_op_mod", "lhs rhs outThrown"),
        opFloorModSpec,
        opLfloorModSpec,
        // UInt/ULong/UByte/UShort division and remainder. Reinterprets both operands
        // as unsigned (UInt(bitPattern:)) instead of the plain signed division
        // kk_op_div/kk_op_mod use, which misreads ULong values with the high bit
        // set (>= 2^63) as negative.
        abi.th("kk_op_udiv", "lhs rhs outThrown"),
        abi.th("kk_op_urem", "lhs rhs outThrown"),
    ]
}
