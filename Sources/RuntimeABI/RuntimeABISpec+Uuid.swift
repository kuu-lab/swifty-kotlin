// KSP-476: only the bridges that genuinely require native support remain.
// Parsing, formatting, bit extraction, comparison, and ByteArray packing are
// pure Kotlin (Sources/CompilerCore/Stdlib/kotlin/uuid/Uuid.kt).

private let abi = RuntimeABISectionBuilder("Uuid")

public extension RuntimeABISpec {
    static let uuidFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_uuid_random"),
        abi.nt("__kk_uuid_lexicalOrder"),
        abi.nt("__kk_uuid_fromLongs", "mostSignificantBits leastSignificantBits"),
        abi.nt("__kk_uuid_toKotlinUuid", "receiver"),
    ]
}
