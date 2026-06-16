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
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_bitwise_or",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_bitwise_xor",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_inv",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_shl",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_shr",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_ushr",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_dmul",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_toString_radix",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "radix", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_countOneBits",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_countLeadingZeroBits",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_countTrailingZeroBits",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        // STDLIB-BIT-007: Additional bit manipulation functions
        RuntimeABIFunctionSpec(
            name: "kk_int_rotateLeft",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "distance", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_rotateRight",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "distance", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_highestOneBit",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_lowestOneBit",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_takeHighestOneBit",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_takeLowestOneBit",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        // Long bit manipulation functions
        RuntimeABIFunctionSpec(
            name: "kk_long_rotateLeft",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "distance", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_rotateRight",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "distance", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_highestOneBit",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_lowestOneBit",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_takeHighestOneBit",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_takeLowestOneBit",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        // Int/Long comparison operators
        RuntimeABIFunctionSpec(
            name: "kk_op_eq",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
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
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_lfloor_div",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
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
    ]

    /// Boolean logical operators
}
