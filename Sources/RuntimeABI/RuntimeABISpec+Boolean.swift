private let abi = RuntimeABISectionBuilder("Boolean")

public extension RuntimeABISpec {
    static let booleanFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("kk_op_not", "value"),
    ]
}
