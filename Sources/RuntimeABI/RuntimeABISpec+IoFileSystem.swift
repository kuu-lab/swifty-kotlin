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
    ]
}
