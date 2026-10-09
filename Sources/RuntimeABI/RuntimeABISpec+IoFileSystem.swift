public extension RuntimeABISpec {
    static let ioFileSystemFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_io_fs_exists",
            parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)],
            returnType: .intptr,
            section: "IoFileSystem",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_io_fs_delete",
            parameters: [
                RuntimeABIParameter(name: "pathRaw", type: .intptr),
                RuntimeABIParameter(name: "mustExist", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "IoFileSystem"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_io_fs_create_directories",
            parameters: [
                RuntimeABIParameter(name: "pathRaw", type: .intptr),
                RuntimeABIParameter(name: "mustCreate", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "IoFileSystem"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_io_fs_atomic_move",
            parameters: [
                RuntimeABIParameter(name: "sourceRaw", type: .intptr),
                RuntimeABIParameter(name: "destinationRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "IoFileSystem"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_io_fs_metadata",
            parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)],
            returnType: .intptr,
            section: "IoFileSystem",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_io_fs_list",
            parameters: [
                RuntimeABIParameter(name: "pathRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "IoFileSystem"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_io_fs_resolve",
            parameters: [
                RuntimeABIParameter(name: "pathRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "IoFileSystem"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_io_fs_open_read",
            parameters: [
                RuntimeABIParameter(name: "pathRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "IoFileSystem"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_io_fs_open_write",
            parameters: [
                RuntimeABIParameter(name: "pathRaw", type: .intptr),
                RuntimeABIParameter(name: "append", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "IoFileSystem"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_io_fs_read",
            parameters: [
                RuntimeABIParameter(name: "descriptor", type: .intptr),
                RuntimeABIParameter(name: "dstRaw", type: .intptr),
                RuntimeABIParameter(name: "dstOffset", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "IoFileSystem"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_io_fs_write",
            parameters: [
                RuntimeABIParameter(name: "descriptor", type: .intptr),
                RuntimeABIParameter(name: "srcRaw", type: .intptr),
                RuntimeABIParameter(name: "srcOffset", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "IoFileSystem"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_io_fs_close",
            parameters: [
                RuntimeABIParameter(name: "descriptor", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "IoFileSystem"
        ),
    ]
}
