public extension RuntimeABISpec {
    static let comparatorFunctions: [RuntimeABIFunctionSpec] = [
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
            name: "__kk_comparable_compareTo",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Comparator",
            isThrowing: false
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
