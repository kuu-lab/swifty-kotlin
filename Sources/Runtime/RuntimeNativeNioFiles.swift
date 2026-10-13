import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private final class RuntimeNativeNioIOExceptionBox: RuntimeIoIOExceptionBox {
    let fqName: String
    init(fqName: String, message: String) {
        self.fqName = fqName
        super.init(message: message)
    }
    override var exceptionFQName: String { fqName }
    override var exceptionHierarchyFQNames: [String] { [fqName] + super.exceptionHierarchyFQNames }
}

private func nativeNioError(path: String, code: Int32) -> Int {
    if code == EEXIST || code == ENOENT {
        return registerRuntimeObject(RuntimeNativeNioIOExceptionBox(
            fqName: code == EEXIST ? "java.nio.file.FileAlreadyExistsException" : "java.nio.file.NoSuchFileException",
            message: path))
    }
    return runtimeAllocateIOException(message: "\(path): \(String(cString: strerror(code)))")
}

/// The option bitset is a private Kotlin/Native declaration-token contract;
/// POSIX flags and descriptor creation never escape into public Kotlin logic.
@_cdecl("__kk_native_filechannel_open")
public func __kk_native_filechannel_open(_ pathRaw: Int, _ options: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    thrown?.pointee = 0
    guard let path = runtimeStringFromRaw(pathRaw) else { fatalError("Invalid Native channel path") }
    let reading = options & 1 != 0
    let writing = options & 2 != 0
    var flags = (reading && writing ? O_RDWR : writing ? O_WRONLY : O_RDONLY) | O_CLOEXEC
    if writing {
        if options & 4 != 0 { flags |= O_APPEND }
        if options & 8 != 0 { flags |= O_CREAT }
        if options & 16 != 0 { flags |= O_CREAT | O_EXCL }
        if options & 32 != 0 { flags |= O_TRUNC }
        if options & 128 != 0 { flags |= O_SYNC }
        if options & 256 != 0 {
            #if canImport(Glibc)
            flags |= O_DSYNC
            #else
            flags |= O_SYNC // Darwin preserves at least the requested data durability.
            #endif
        }
    }
    if options & 512 != 0 { flags |= O_NOFOLLOW }
    let fd = path.withCString { open($0, flags, mode_t(0o666)) }
    if fd < 0 { thrown?.pointee = nativeNioError(path: path, code: errno); return -1 }
    var info = stat()
    let statResult = fstat(fd, &info)
    if statResult != 0 || (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) {
        let code = statResult != 0 ? errno : EISDIR
        close(fd)
        thrown?.pointee = nativeNioError(path: path, code: code)
        return -1
    }
    if options & 64 != 0, path.withCString({ unlink($0) }) != 0 {
        let code = errno
        close(fd)
        thrown?.pointee = nativeNioError(path: path, code: code)
        return -1
    }
    return Int(fd)
}

/// A channel write returns the actual single-write count. The common file sink
/// full-write loop is kept untouched; Kotlin advances ByteBuffer by this count.
@_cdecl("__kk_native_filechannel_write")
public func __kk_native_filechannel_write(_ descriptor: Int, _ bytesRaw: Int, _ offset: Int, _ count: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    thrown?.pointee = 0
    let array = runtimeArrayBox(from: bytesRaw)
    let list = runtimeListBox(from: bytesRaw)
    guard let size = array?.count ?? list?.count, offset >= 0, count >= 0, offset <= size - count else {
        thrown?.pointee = runtimeAllocateIndexOutOfBoundsException(message: "Invalid channel byte range")
        return 0
    }
    guard descriptor >= 0, descriptor <= Int(Int32.max) else {
        thrown?.pointee = runtimeAllocateIOException(message: "Invalid channel descriptor")
        return 0
    }
    if count == 0 { return 0 }
    let bytes = (offset..<offset + count).map { UInt8(truncatingIfNeeded: array?[$0] ?? kk_unbox_int(list?[$0] ?? 0)) }
    var code: Int32 = 0
    let result = bytes.withUnsafeBytes { buffer -> Int in
        guard let base = buffer.baseAddress else { return 0 }
        while true {
            let n = write(Int32(descriptor), base, count)
            if n < 0 && errno == EINTR { continue }
            if n < 0 { code = errno }
            return n
        }
    }
    if result < 0 { thrown?.pointee = runtimeAllocateIOException(message: String(cString: strerror(code))); return 0 }
    return result
}

@_cdecl("__kk_native_nio_create_file")
public func __kk_native_nio_create_file(_ pathRaw: Int, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    thrown?.pointee = 0
    guard let path = runtimeStringFromRaw(pathRaw) else { fatalError("Invalid Native file path") }
    let fd = path.withCString { open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode_t(0o666)) }
    if fd < 0 { thrown?.pointee = nativeNioError(path: path, code: errno); return 0 }
    if close(fd) != 0 { thrown?.pointee = nativeNioError(path: path, code: errno) }
    return 0
}
