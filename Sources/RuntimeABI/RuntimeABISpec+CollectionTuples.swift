private let abi = RuntimeABISectionBuilder("Collection")

public extension RuntimeABISpec {
    static let collectionTupleFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_pair_new", "first second"),
        abi.nt("__kk_pair_first", "pairRaw"),
        abi.nt("__kk_pair_second", "pairRaw"),
        abi.nt("__kk_triple_new", "first second third"),
        abi.nt("__kk_triple_first", "tripleRaw"),
        abi.nt("__kk_triple_second", "tripleRaw"),
        abi.nt("__kk_triple_third", "tripleRaw"),
    ]
}
