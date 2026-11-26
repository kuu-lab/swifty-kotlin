private let abi = RuntimeABISectionBuilder("Uuid")

public extension RuntimeABISpec {
    static let uuidFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_uuid_random"),
        abi.nt("__kk_uuid_lexicalOrder"),
        abi.nt("__kk_uuid_fromLongs", "mostSignificantBits leastSignificantBits"),
        abi.nt("__kk_uuid_toKotlinUuid", "receiver"),
    ]
}
