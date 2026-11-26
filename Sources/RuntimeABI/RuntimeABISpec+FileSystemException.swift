private let fileSystemExceptionABI = RuntimeABISectionBuilder("FileSystemException")

public extension RuntimeABISpec {
    static let fileSystemExceptionFunctions: [RuntimeABIFunctionSpec] = [
        fileSystemExceptionABI.nt("__kk_file_system_exception_new_file", "fileRaw"),
        fileSystemExceptionABI.nt("__kk_file_system_exception_new_file_other", "fileRaw otherRaw"),
        fileSystemExceptionABI.nt("__kk_file_system_exception_new_file_other_reason", "fileRaw otherRaw reasonRaw"),
        fileSystemExceptionABI.nt("__kk_file_already_exists_exception_new_file", "fileRaw"),
        fileSystemExceptionABI.nt("__kk_file_already_exists_exception_new_file_other", "fileRaw otherRaw"),
        fileSystemExceptionABI.nt("__kk_file_already_exists_exception_new_file_other_reason", "fileRaw otherRaw reasonRaw"),
        fileSystemExceptionABI.nt("__kk_access_denied_exception_new_file", "fileRaw"),
        fileSystemExceptionABI.nt("__kk_access_denied_exception_new_file_other", "fileRaw otherRaw"),
        fileSystemExceptionABI.nt("__kk_access_denied_exception_new_file_other_reason", "fileRaw otherRaw reasonRaw"),
        fileSystemExceptionABI.nt("__kk_no_such_file_exception_new_file", "fileRaw"),
        fileSystemExceptionABI.nt("__kk_no_such_file_exception_new_file_other", "fileRaw otherRaw"),
        fileSystemExceptionABI.nt("__kk_no_such_file_exception_new_file_other_reason", "fileRaw otherRaw reasonRaw"),
        fileSystemExceptionABI.nt("__kk_file_system_exception_file", "selfRaw"),
        fileSystemExceptionABI.nt("__kk_file_system_exception_other", "selfRaw"),
        fileSystemExceptionABI.nt("__kk_file_system_exception_reason", "selfRaw"),
    ]
}
