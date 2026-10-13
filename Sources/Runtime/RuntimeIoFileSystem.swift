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

private func ioFileSystemByteArrayLength(_ raw: Int) -> Int? {
    if let array = runtimeArrayBox(from: raw) { return array.count }
    if let list = runtimeListBox(from: raw) { return list.count }
    return nil
}

private func ioFileSystemByteSlice(_ raw: Int, offset: Int, count: Int) -> [UInt8]? {
    if let array = runtimeArrayBox(from: raw) {
        guard offset >= 0, count >= 0, offset + count <= array.count else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(count)
        for index in 0 ..< count {
            bytes.append(UInt8(truncatingIfNeeded: array[offset + index]))
        }
        return bytes
    }
    if let list = runtimeListBox(from: raw) {
        guard offset >= 0, count >= 0, offset + count <= list.count else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(count)
        for index in 0 ..< count {
            bytes.append(UInt8(truncatingIfNeeded: kk_unbox_int(list[offset + index])))
        }
        return bytes
    }
    return nil
}

private func ioFileSystemStoreBytes(_ raw: Int, offset: Int, bytes: [UInt8]) -> Bool {
    if let array = runtimeArrayBox(from: raw) {
        guard offset >= 0, offset + bytes.count <= array.count else { return false }
        for (index, byte) in bytes.enumerated() {
            array[offset + index] = Int(Int8(bitPattern: byte))
        }
        return true
    }
    if let list = runtimeListBox(from: raw) {
        guard offset >= 0, offset + bytes.count <= list.count else { return false }
        for (index, byte) in bytes.enumerated() {
            list[offset + index] = Int(Int8(bitPattern: byte))
        }
        return true
    }
    return false
}

private func ioFileSystemClosedError() -> Int {
    ioFileSystemError("Stream Closed")
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

// FileSource/FileSink bridges. Open failures always surface as
// FileNotFoundException to match the JVM reference implementation
// (`FileInputStream(path)` / `FileOutputStream(path, append)` in
// kotlinx-io core/jvm/src/files/PathsJvm.kt), including EISDIR and EACCES.

@_cdecl("__kk_io_fs_open_read")
public func __kk_io_fs_open_read(_ pathRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let path = ioFileSystemPath(pathRaw)
    let descriptor = open(path, O_RDONLY)
    if descriptor < 0 {
        let code = errno
        outThrown?.pointee = ioFileSystemError(
            "Open failed for \(path): \(String(cString: strerror(code)))", missing: true
        )
        return -1
    }
    var info = stat()
    if fstat(descriptor, &info) != 0 || (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) {
        close(descriptor)
        outThrown?.pointee = ioFileSystemError(
            "Open failed for \(path): \(String(cString: strerror(EISDIR)))", missing: true
        )
        return -1
    }
    return Int(descriptor)
}

@_cdecl("__kk_io_fs_open_write")
public func __kk_io_fs_open_write(
    _ pathRaw: Int, _ append: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let path = ioFileSystemPath(pathRaw)
    let flags = O_WRONLY | O_CREAT | (append != 0 ? O_APPEND : O_TRUNC)
    let descriptor = open(path, flags, 0o666)
    if descriptor < 0 {
        let code = errno
        outThrown?.pointee = ioFileSystemError(
            "Open failed for \(path): \(String(cString: strerror(code)))", missing: true
        )
        return -1
    }
    return Int(descriptor)
}

@_cdecl("__kk_io_fs_read")
public func __kk_io_fs_read(
    _ descriptor: Int,
    _ dstRaw: Int,
    _ dstOffset: Int,
    _ byteCount: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard descriptor >= 0 else {
        outThrown?.pointee = ioFileSystemClosedError()
        return 0
    }
    guard byteCount >= 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "byteCount (\(byteCount)) < 0"
        )
        return 0
    }
    guard byteCount > 0 else { return 0 }
    guard let dstLength = ioFileSystemByteArrayLength(dstRaw),
          dstOffset >= 0, dstOffset + byteCount <= dstLength
    else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Destination range [\(dstOffset), \(dstOffset + byteCount)) is out of bounds."
        )
        return 0
    }
    let fd = Int32(descriptor)
    var readError: Int32 = 0
    var scratch = [UInt8](repeating: 0, count: byteCount)
    let readCount = scratch.withUnsafeMutableBytes { buffer -> Int in
        guard let base = buffer.baseAddress else { return 0 }
        while true {
            let result = read(fd, base, byteCount)
            if result < 0 {
                if errno == EINTR { continue }
                readError = errno
                return -1
            }
            return result
        }
    }
    if readCount < 0 {
        outThrown?.pointee = ioFileSystemError("Read failed: \(String(cString: strerror(readError)))")
        return 0
    }
    if readCount > 0, !ioFileSystemStoreBytes(dstRaw, offset: dstOffset, bytes: Array(scratch[0 ..< readCount])) {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Destination range [\(dstOffset), \(dstOffset + readCount)) is out of bounds."
        )
        return 0
    }
    return readCount
}

@_cdecl("__kk_io_fs_write")
public func __kk_io_fs_write(
    _ descriptor: Int,
    _ srcRaw: Int,
    _ srcOffset: Int,
    _ byteCount: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard descriptor >= 0 else {
        outThrown?.pointee = ioFileSystemClosedError()
        return 0
    }
    guard byteCount >= 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "byteCount (\(byteCount)) < 0"
        )
        return 0
    }
    guard byteCount > 0 else { return 0 }
    guard let bytes = ioFileSystemByteSlice(srcRaw, offset: srcOffset, count: byteCount) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Source range [\(srcOffset), \(srcOffset + byteCount)) is out of bounds."
        )
        return 0
    }
    let fd = Int32(descriptor)
    var writeError: Int32 = EIO
    let writeResult = bytes.withUnsafeBytes { buffer -> Int in
        guard let base = buffer.baseAddress else { return -1 }
        var writtenTotal = 0
        while writtenTotal < bytes.count {
            let result = write(fd, base.advanced(by: writtenTotal), bytes.count - writtenTotal)
            if result < 0 {
                if errno == EINTR { continue }
                writeError = errno
                return -1
            }
            if result == 0 { return -1 }
            writtenTotal += result
        }
        return writtenTotal
    }
    if writeResult < 0 {
        outThrown?.pointee = ioFileSystemError("Write failed: \(String(cString: strerror(writeError)))")
    }
    return 0
}

@_cdecl("__kk_io_fs_close")
public func __kk_io_fs_close(_ descriptor: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard descriptor >= 0 else {
        outThrown?.pointee = ioFileSystemClosedError()
        return 0
    }
    if close(Int32(descriptor)) != 0 {
        let code = errno
        outThrown?.pointee = ioFileSystemError("Close failed: \(String(cString: strerror(code)))")
    }
    return 0
}
