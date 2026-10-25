private let abi = RuntimeABISectionBuilder("Enum")

public extension RuntimeABISpec {
    static let enumFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("kk_enum_hash_code", "ordinal classID"),
        abi.nt("kk_enum_compareTo", "ordinal otherOrdinal"),
    ]
}
