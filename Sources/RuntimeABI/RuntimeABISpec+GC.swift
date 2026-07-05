// swiftlint:disable file_length

/// `RuntimeABISpec.gcFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
    static let gcFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_register_global_root",
            parameters: [
                RuntimeABIParameter(name: "slot", type: .nullableRawPointerPointer),
            ],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unregister_global_root",
            parameters: [
                RuntimeABIParameter(name: "slot", type: .nullableRawPointerPointer),
            ],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_register_frame_map",
            parameters: [
                RuntimeABIParameter(name: "functionID", type: .uint32),
                RuntimeABIParameter(name: "mapPtr", type: .nullableConstRawPointer),
            ],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_push_frame",
            parameters: [
                RuntimeABIParameter(name: "functionID", type: .uint32),
                RuntimeABIParameter(name: "frameBase", type: .nullableOpaquePointer),
            ],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_pop_frame",
            parameters: [],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_register_coroutine_root",
            parameters: [
                RuntimeABIParameter(name: "value", type: .nullableOpaquePointer),
            ],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unregister_coroutine_root",
            parameters: [
                RuntimeABIParameter(name: "value", type: .nullableOpaquePointer),
            ],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_heap_object_count",
            parameters: [],
            returnType: .uint32,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_force_reset",
            parameters: [],
            returnType: .void,
            section: "GC"
        ),
    ]
}
