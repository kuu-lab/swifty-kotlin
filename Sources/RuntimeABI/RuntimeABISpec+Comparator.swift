public extension RuntimeABISpec {
    static let comparatorFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_compare_with_comparator",
            parameters: [
                RuntimeABIParameter(name: "comparator", type: .intptr),
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_comparable_compareTo",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Comparator",
            isThrowing: false
        ),
        // `String.CASE_INSENSITIVE_ORDER` stays runtime backed: it is a companion
        // `val`, so every read has to observe the same comparator instance
        // (BUG-036/BUG-154), which the runtime singleton guarantees.
        RuntimeABIFunctionSpec(
            name: "kk_string_case_insensitive_order_trampoline",
            parameters: [
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_case_insensitive_order",
            parameters: [],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_primitive_compareTo",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
                RuntimeABIParameter(name: "kindRaw", type: .int32),
            ],
            returnType: .intptr,
            section: "Comparator",
            isThrowing: false
        ),
    ]
}
