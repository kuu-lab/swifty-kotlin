// swiftlint:disable file_length

/// `RuntimeABISpec.memoryFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
    static let memoryFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_alloc",
            parameters: [
                RuntimeABIParameter(name: "size", type: .uint32),
                RuntimeABIParameter(name: "typeInfo", type: .constTypeInfoPointer),
            ],
            returnType: .opaquePointer,
            section: "Memory"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_gc_collect",
            parameters: [],
            returnType: .void,
            section: "Memory",
            isThrowing: false,
        ),
    ]
}
