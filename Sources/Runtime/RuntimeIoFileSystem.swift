import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

class RuntimeIoIOExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String { "kotlinx.io.IOException" }
    override var exceptionHierarchyFQNames: [String] {
        ["kotlinx.io.IOException", "java.io.IOException", "kotlin.Exception", "kotlin.Throwable"]
    }
    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("IOException", message)
    }
}

final class RuntimeIoFileNotFoundExceptionBox: RuntimeIoIOExceptionBox {
    override var exceptionFQName: String { "kotlinx.io.files.FileNotFoundException" }
    override var exceptionHierarchyFQNames: [String] {
        [exceptionFQName, "java.io.FileNotFoundException"] + super.exceptionHierarchyFQNames
    }
    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("FileNotFoundException", message)
    }
}

private func ioFileSystemPath(_ raw: Int) -> String {
    extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
}

private func ioFileSystemError(_ message: String, missing: Bool = false) -> Int {
    let error: RuntimeThrowableBox = missing
        ? RuntimeIoFileNotFoundExceptionBox(message: message)
        : RuntimeIoIOExceptionBox(message: message)
    return registerRuntimeObject(error)
}

private func ioFileSystemStat(_ path: String) -> stat? {
    var info = stat()
    return fstatat(AT_FDCWD, path, &info, 0) == 0 ? info : nil
}

@_cdecl("__kk_io_fs_exists")
public func __kk_io_fs_exists(_ pathRaw: Int) -> Int {
    access(ioFileSystemPath(pathRaw), F_OK) == 0 ? 1 : 0
}

@_cdecl("__kk_io_fs_delete")
public func __kk_io_fs_delete(_ pathRaw: Int, _ mustExist: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let path = ioFileSystemPath(pathRaw)
    if remove(path) != 0 {
        let code = errno
        if code == ENOENT && mustExist == 0 { return 0 }
        outThrown?.pointee = ioFileSystemError(
            "Delete failed for \(path): \(String(cString: strerror(code)))", missing: code == ENOENT
        )
    }
    return 0
}

@_cdecl("__kk_io_fs_create_directories")
public func __kk_io_fs_create_directories(
    _ pathRaw: Int, _ mustCreate: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let path = ioFileSystemPath(pathRaw)
    if let info = ioFileSystemStat(path) {
        if mustCreate != 0 || (info.st_mode & mode_t(S_IFMT)) != mode_t(S_IFDIR) {
            outThrown?.pointee = ioFileSystemError("Path already exists: \(path)")
        }
        return 0
    }
    do {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    } catch {
        outThrown?.pointee = ioFileSystemError(error.localizedDescription)
    }
    return 0
}

@_cdecl("__kk_io_fs_atomic_move")
public func __kk_io_fs_atomic_move(
    _ sourceRaw: Int, _ destinationRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = ioFileSystemPath(sourceRaw)
    let destination = ioFileSystemPath(destinationRaw)
    if access(source, F_OK) != 0 {
        outThrown?.pointee = ioFileSystemError("Source does not exist: \(source)", missing: true)
        return 0
    }
    if rename(source, destination) != 0 {
        let code = errno
        let message = "Move failed for \(source) to \(destination): \(String(cString: strerror(code)))"
        outThrown?.pointee = code == EXDEV
            ? runtimeAllocateUnsupportedOperationException(message: message)
            : ioFileSystemError(message)
    }
    return 0
}

@_cdecl("__kk_io_fs_metadata")
public func __kk_io_fs_metadata(_ pathRaw: Int) -> Int {
    guard let info = ioFileSystemStat(ioFileSystemPath(pathRaw)) else { return runtimeNullSentinelInt }
    let kind = info.st_mode & mode_t(S_IFMT)
    let regular = kind == mode_t(S_IFREG)
    let result = kk_array_new(3)
    _ = kk_array_set(result, 0, regular ? 1 : 0, nil)
    _ = kk_array_set(result, 1, kind == mode_t(S_IFDIR) ? 1 : 0, nil)
    _ = kk_array_set(result, 2, regular ? Int(info.st_size) : -1, nil)
    return result
}

@_cdecl("__kk_io_fs_list")
public func __kk_io_fs_list(_ pathRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let path = ioFileSystemPath(pathRaw)
    guard let info = ioFileSystemStat(path) else {
        outThrown?.pointee = ioFileSystemError("Directory does not exist: \(path)", missing: true)
        return runtimeNullSentinelInt
    }
    guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
        outThrown?.pointee = ioFileSystemError("Not a directory: \(path)")
        return runtimeNullSentinelInt
    }
    do {
        return runtimeMakeStringListRaw(try FileManager.default.contentsOfDirectory(atPath: path))
    } catch {
        outThrown?.pointee = ioFileSystemError(error.localizedDescription)
        return runtimeNullSentinelInt
    }
}

@_cdecl("__kk_io_fs_resolve")
public func __kk_io_fs_resolve(_ pathRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let path = ioFileSystemPath(pathRaw)
    guard let resolved = realpath(path, nil) else {
        let code = errno
        outThrown?.pointee = ioFileSystemError(
            "Resolve failed for \(path): \(String(cString: strerror(code)))", missing: code == ENOENT
        )
        return runtimeNullSentinelInt
    }
    defer { free(resolved) }
    return runtimeMakeStringRaw(String(cString: resolved))
}
