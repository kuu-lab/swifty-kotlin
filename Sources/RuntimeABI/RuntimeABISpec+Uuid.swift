// Uuid functions (kotlin.uuid.Uuid).
//
// KSP-476: only the bridges that genuinely require native support remain.
// Parsing, formatting, bit extraction, comparison, and ByteArray packing are
// pure Kotlin (Sources/CompilerCore/Stdlib/kotlin/uuid/Uuid.kt).

public extension RuntimeABISpec {
    static let uuidFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_uuid_random",
            parameters: [],
            returnType: .intptr,
            section: "Uuid",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uuid_mostSignificantBits",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Uuid",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uuid_leastSignificantBits",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Uuid",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uuid_nameUUIDFromBytes",
            parameters: [
                RuntimeABIParameter(name: "nameArray", type: .intptr),
            ],
            returnType: .intptr,
            section: "Uuid",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uuid_fromLongs",
            parameters: [
                RuntimeABIParameter(name: "mostSignificantBits", type: .intptr),
                RuntimeABIParameter(name: "leastSignificantBits", type: .intptr),
            ],
            returnType: .intptr,
            section: "Uuid",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uuid_toKotlinUuid",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Uuid",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uuid_lexicalOrder",
            parameters: [],
            returnType: .intptr,
            section: "Uuid",
            isThrowing: false
        ),
    ]
}
