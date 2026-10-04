import Foundation

// MARK: - kotlin.io filesystem exceptions (KSP-619 / BUG-016)
//
// Storage for the `kotlin.io.FileSystemException` hierarchy declared in
// Sources/CompilerCore/Stdlib/kotlin/io/FileSystemException.kt. Both Kotlin
// `throw FileAlreadyExistsException(file)` sites and runtime-internal failures
// (File.copyTo, Files.delete, …) allocate the boxes below, so catch-clause
// dispatch and the `file` / `other` / `reason` accessors observe the same
// representation regardless of where the exception originated.

/// Builds the `message` text of a filesystem exception the same way
/// `kotlin.io.FileSystemException` does: `file[ -> other][: reason]`.
func runtimeFileSystemExceptionMessage(file: String, other: String?, reason: String?) -> String {
    var text = file
    if let other {
        text += " -> \(other)"
    }
    if let reason {
        text += ": \(reason)"
    }
    return text
}

class RuntimeFileSystemExceptionBox: RuntimeThrowableBox {
    let fileRaw: Int
    let otherRaw: Int
    let reason: String?

    init(fileRaw: Int, otherRaw: Int, reason: String?) {
        self.fileRaw = fileRaw
        self.otherRaw = otherRaw
        self.reason = reason
        super.init(message: runtimeFileSystemExceptionMessage(
            file: runtimeFileSystemExceptionPath(from: fileRaw) ?? "null",
            other: runtimeFileSystemExceptionPath(from: otherRaw),
            reason: reason
        ))
    }

    override var exceptionFQName: String {
        "kotlin.io.FileSystemException"
    }

    override var exceptionHierarchyFQNames: [String] {
        var names = [exceptionFQName]
        if exceptionFQName != "kotlin.io.FileSystemException" {
            names.append("kotlin.io.FileSystemException")
        }
        names.append("kotlin.Exception")
        names.append("kotlin.Throwable")
        return names
    }
}

final class RuntimeFileAlreadyExistsExceptionBox: RuntimeFileSystemExceptionBox {
    override var exceptionFQName: String {
        "kotlin.io.FileAlreadyExistsException"
    }
}

final class RuntimeAccessDeniedExceptionBox: RuntimeFileSystemExceptionBox {
    override var exceptionFQName: String {
        "kotlin.io.AccessDeniedException"
    }
}

final class RuntimeNoSuchFileExceptionBox: RuntimeFileSystemExceptionBox {
    override var exceptionFQName: String {
        "kotlin.io.NoSuchFileException"
    }
}

private func runtimeFileSystemExceptionBox(from raw: Int) -> RuntimeFileSystemExceptionBox? {
    guard let ptr = normalizeNullableRuntimePointer(UnsafeMutableRawPointer(bitPattern: raw)) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeFileSystemExceptionBox.self)
}

/// Reads the path out of a `java.io.File` handle, tolerating null handles.
private func runtimeFileSystemExceptionPath(from raw: Int) -> String? {
    guard let ptr = normalizeNullableRuntimePointer(UnsafeMutableRawPointer(bitPattern: raw)) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeFileBox.self)?.path
}

/// Normalizes a nullable object argument to `0` so the boxes never retain a
/// null-sentinel handle.
private func runtimeFileSystemExceptionHandle(_ raw: Int) -> Int {
    normalizeNullableRuntimePointer(UnsafeMutableRawPointer(bitPattern: raw)) == nil ? 0 : raw
}

private func runtimeFileHandle(path: String) -> Int {
    registerRuntimeObject(RuntimeFileBox(path))
}

// MARK: - Runtime-internal allocation helpers

func runtimeAllocateFileSystemException(file: String, other: String? = nil, reason: String? = nil) -> Int {
    registerRuntimeObject(RuntimeFileSystemExceptionBox(
        fileRaw: runtimeFileHandle(path: file),
        otherRaw: other.map { runtimeFileHandle(path: $0) } ?? 0,
        reason: reason
    ))
}

func runtimeAllocateFileAlreadyExistsException(file: String, other: String? = nil, reason: String? = nil) -> Int {
    registerRuntimeObject(RuntimeFileAlreadyExistsExceptionBox(
        fileRaw: runtimeFileHandle(path: file),
        otherRaw: other.map { runtimeFileHandle(path: $0) } ?? 0,
        reason: reason
    ))
}

func runtimeAllocateNoSuchFileException(file: String, other: String? = nil, reason: String? = nil) -> Int {
    registerRuntimeObject(RuntimeNoSuchFileExceptionBox(
        fileRaw: runtimeFileHandle(path: file),
        otherRaw: other.map { runtimeFileHandle(path: $0) } ?? 0,
        reason: reason
    ))
}

func runtimeAllocateAccessDeniedException(file: String, other: String? = nil, reason: String? = nil) -> Int {
    registerRuntimeObject(RuntimeAccessDeniedExceptionBox(
        fileRaw: runtimeFileHandle(path: file),
        otherRaw: other.map { runtimeFileHandle(path: $0) } ?? 0,
        reason: reason
    ))
}

// MARK: - Kotlin-facing bridges
//
// One entry point per (class, arity): the constructor overloads declared in
// Stdlib/kotlin/io/FileSystemException.kt bind to these directly.

private func runtimeMakeFileSystemException<Box: RuntimeFileSystemExceptionBox>(
    _ makeBox: (Int, Int, String?) -> Box,
    _ fileRaw: Int,
    _ otherRaw: Int,
    _ reasonRaw: Int
) -> Int {
    registerRuntimeObject(makeBox(
        runtimeFileSystemExceptionHandle(fileRaw),
        runtimeFileSystemExceptionHandle(otherRaw),
        extractString(from: UnsafeMutableRawPointer(bitPattern: reasonRaw))
    ))
}

@_cdecl("__kk_file_system_exception_new_file")
public func __kk_file_system_exception_new_file(_ fileRaw: Int) -> Int {
    runtimeMakeFileSystemException(RuntimeFileSystemExceptionBox.init, fileRaw, 0, 0)
}

@_cdecl("__kk_file_system_exception_new_file_other")
public func __kk_file_system_exception_new_file_other(_ fileRaw: Int, _ otherRaw: Int) -> Int {
    runtimeMakeFileSystemException(RuntimeFileSystemExceptionBox.init, fileRaw, otherRaw, 0)
}

@_cdecl("__kk_file_system_exception_new_file_other_reason")
public func __kk_file_system_exception_new_file_other_reason(
    _ fileRaw: Int,
    _ otherRaw: Int,
    _ reasonRaw: Int
) -> Int {
    runtimeMakeFileSystemException(RuntimeFileSystemExceptionBox.init, fileRaw, otherRaw, reasonRaw)
}

@_cdecl("__kk_file_already_exists_exception_new_file")
public func __kk_file_already_exists_exception_new_file(_ fileRaw: Int) -> Int {
    runtimeMakeFileSystemException(RuntimeFileAlreadyExistsExceptionBox.init, fileRaw, 0, 0)
}

@_cdecl("__kk_file_already_exists_exception_new_file_other")
public func __kk_file_already_exists_exception_new_file_other(_ fileRaw: Int, _ otherRaw: Int) -> Int {
    runtimeMakeFileSystemException(RuntimeFileAlreadyExistsExceptionBox.init, fileRaw, otherRaw, 0)
}

@_cdecl("__kk_file_already_exists_exception_new_file_other_reason")
public func __kk_file_already_exists_exception_new_file_other_reason(
    _ fileRaw: Int,
    _ otherRaw: Int,
    _ reasonRaw: Int
) -> Int {
    runtimeMakeFileSystemException(RuntimeFileAlreadyExistsExceptionBox.init, fileRaw, otherRaw, reasonRaw)
}

@_cdecl("__kk_access_denied_exception_new_file")
public func __kk_access_denied_exception_new_file(_ fileRaw: Int) -> Int {
    runtimeMakeFileSystemException(RuntimeAccessDeniedExceptionBox.init, fileRaw, 0, 0)
}

@_cdecl("__kk_access_denied_exception_new_file_other")
public func __kk_access_denied_exception_new_file_other(_ fileRaw: Int, _ otherRaw: Int) -> Int {
    runtimeMakeFileSystemException(RuntimeAccessDeniedExceptionBox.init, fileRaw, otherRaw, 0)
}

@_cdecl("__kk_access_denied_exception_new_file_other_reason")
public func __kk_access_denied_exception_new_file_other_reason(
    _ fileRaw: Int,
    _ otherRaw: Int,
    _ reasonRaw: Int
) -> Int {
    runtimeMakeFileSystemException(RuntimeAccessDeniedExceptionBox.init, fileRaw, otherRaw, reasonRaw)
}

@_cdecl("__kk_no_such_file_exception_new_file")
public func __kk_no_such_file_exception_new_file(_ fileRaw: Int) -> Int {
    runtimeMakeFileSystemException(RuntimeNoSuchFileExceptionBox.init, fileRaw, 0, 0)
}

@_cdecl("__kk_no_such_file_exception_new_file_other")
public func __kk_no_such_file_exception_new_file_other(_ fileRaw: Int, _ otherRaw: Int) -> Int {
    runtimeMakeFileSystemException(RuntimeNoSuchFileExceptionBox.init, fileRaw, otherRaw, 0)
}

@_cdecl("__kk_no_such_file_exception_new_file_other_reason")
public func __kk_no_such_file_exception_new_file_other_reason(
    _ fileRaw: Int,
    _ otherRaw: Int,
    _ reasonRaw: Int
) -> Int {
    runtimeMakeFileSystemException(RuntimeNoSuchFileExceptionBox.init, fileRaw, otherRaw, reasonRaw)
}

@_cdecl("__kk_file_system_exception_file")
public func __kk_file_system_exception_file(_ selfRaw: Int) -> Int {
    guard let box = runtimeFileSystemExceptionBox(from: selfRaw), box.fileRaw != 0 else {
        return runtimeNullSentinelInt
    }
    return box.fileRaw
}

@_cdecl("__kk_file_system_exception_other")
public func __kk_file_system_exception_other(_ selfRaw: Int) -> Int {
    guard let box = runtimeFileSystemExceptionBox(from: selfRaw), box.otherRaw != 0 else {
        return runtimeNullSentinelInt
    }
    return box.otherRaw
}

@_cdecl("__kk_file_system_exception_reason")
public func __kk_file_system_exception_reason(_ selfRaw: Int) -> Int {
    guard let box = runtimeFileSystemExceptionBox(from: selfRaw), let reason = box.reason else {
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(RuntimeStringBox(reason))
}
