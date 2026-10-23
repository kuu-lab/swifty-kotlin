private let abi = RuntimeABISectionBuilder("Memory")

public extension RuntimeABISpec {
    static let allocSpec: RuntimeABIFunctionSpec = abi.th("kk_alloc", "size:uint32 typeInfo:constTypeInfoPointer", ret: .opaquePointer)
    static let gcCollectSpec: RuntimeABIFunctionSpec = abi.nt("kk_gc_collect", "gcRaw", ret: .void)

    static let memoryFunctions: [RuntimeABIFunctionSpec] = [
        allocSpec,
        gcCollectSpec,
    ]
}
