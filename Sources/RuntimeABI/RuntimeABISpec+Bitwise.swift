// swiftlint:disable file_length

/// `RuntimeABISpec.bitwiseFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
    /// Bitwise/Shift (P5-103)
    static let bitwiseFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_bitwise_and",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_bitwise_or",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_bitwise_xor",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_inv",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_shl",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_shr",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_ushr",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_dmul",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_toString_radix",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "radix", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Bitwise",
            isThrowing: false
        ),
        // STDLIB-BIT-007: One-bit functions are source-backed in
        // `Stdlib/kotlin/BitOperations.kt` since KSP-644.
        // Int/Long comparison operators
        RuntimeABIFunctionSpec(
            name: "kk_op_eq",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_ne",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_lt",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_le",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_gt",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_ge",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        // Unsigned (ULong-correct) comparison operators
        RuntimeABIFunctionSpec(
            name: "kk_op_ult",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_ule",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_ugt",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_uge",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        // Int/Long truncating division and remainder — throwing (PEC-NUM-0002)
        RuntimeABIFunctionSpec(
            name: "kk_op_div",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        // Int/Long flooring division and modulo operators
        RuntimeABIFunctionSpec(
            name: "kk_op_floor_div",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_lfloor_div",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_mod",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_floor_mod",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_lfloor_mod",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        // UInt/ULong/UByte/UShort division and remainder — throwing (PEC-NUM-0002 / KSP-466).
        // Reinterprets both operands as unsigned (UInt(bitPattern:)) instead of the
        // plain signed division kk_op_div/kk_op_mod use, which misreads ULong values
        // with the high bit set (>= 2^63) as negative.
        RuntimeABIFunctionSpec(
            name: "kk_op_udiv",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_urem",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
    ]

    /// Boolean logical operators
}
