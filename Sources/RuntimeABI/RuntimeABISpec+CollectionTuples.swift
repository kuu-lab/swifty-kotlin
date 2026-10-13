/// Pair and Triple ABI specs split out from `RuntimeABISpec+Collection.swift`.
public extension RuntimeABISpec {
    static let collectionTupleFunctions: [RuntimeABIFunctionSpec] = [
        // Pair (FUNC-002)
        RuntimeABIFunctionSpec(
            name: "__kk_pair_new",
            parameters: [
                RuntimeABIParameter(name: "first", type: .intptr),
                RuntimeABIParameter(name: "second", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_pair_first",
            parameters: [
                RuntimeABIParameter(name: "pairRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_pair_second",
            parameters: [
                RuntimeABIParameter(name: "pairRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        // Triple (STDLIB-120)
        RuntimeABIFunctionSpec(
            name: "__kk_triple_new",
            parameters: [
                RuntimeABIParameter(name: "first", type: .intptr),
                RuntimeABIParameter(name: "second", type: .intptr),
                RuntimeABIParameter(name: "third", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_triple_first",
            parameters: [
                RuntimeABIParameter(name: "tripleRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_triple_second",
            parameters: [
                RuntimeABIParameter(name: "tripleRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_triple_third",
            parameters: [
                RuntimeABIParameter(name: "tripleRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
    ]
}
