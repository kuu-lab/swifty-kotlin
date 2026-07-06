// Uuid functions (kotlin.uuid.Uuid).

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
            name: "__kk_uuid_nameUUIDFromBytes",
            parameters: [
                RuntimeABIParameter(name: "nameArray", type: .intptr),
            ],
            returnType: .intptr,
            section: "Uuid",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uuid_toKotlinUuid",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Uuid",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_byteArray_putUuid",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "at", type: .intptr),
                RuntimeABIParameter(name: "uuid", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Uuid"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_byteArray_uuid",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "at", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Uuid"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uuid_getUuid",
            parameters: [
                RuntimeABIParameter(name: "byteArray", type: .intptr),
                RuntimeABIParameter(name: "offset", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Uuid"
        ),
    ]
}
