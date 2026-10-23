private let abi = RuntimeABISectionBuilder("IoFileSystem")

public extension RuntimeABISpec {
    static let ioFileSystemFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_io_fs_temporary_directory"),
        abi.nt("__kk_io_fs_exists", "pathRaw"),
        abi.th("__kk_io_fs_delete", "pathRaw mustExist outThrown"),
        abi.th("__kk_io_fs_create_directories", "pathRaw mustCreate outThrown"),
        abi.th("__kk_io_fs_atomic_move", "sourceRaw destinationRaw outThrown"),
        abi.nt("__kk_io_fs_metadata", "pathRaw"),
        abi.th("__kk_io_fs_list", "pathRaw outThrown"),
        abi.th("__kk_io_fs_resolve", "pathRaw outThrown"),
        abi.th("__kk_io_fs_open_read", "pathRaw outThrown"),
        abi.th("__kk_io_fs_open_write", "pathRaw append outThrown"),
        abi.th("__kk_io_fs_read", "descriptor dstRaw dstOffset byteCount outThrown"),
        abi.th("__kk_io_fs_write", "descriptor srcRaw srcOffset byteCount outThrown"),
        abi.th("__kk_io_fs_close", "descriptor outThrown"),
    ]
}
