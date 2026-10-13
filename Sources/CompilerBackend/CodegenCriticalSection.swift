import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import CompilerCore

enum CodegenCriticalSection {
    /// LLVM's target registry is process-global and is not safe to touch
    /// concurrently, even when each compilation owns a separate context and
    /// output path. Cross-process serialization is unnecessary because each
    /// `kswiftc` process has its own LLVM target registry.
    static func withLinuxLLVMProcessLock<T>(
        target: TargetTriple,
        body: () throws -> T
    ) rethrows -> T {
        guard target.os.hasPrefix("linux") else {
            return try body()
        }

        linuxLLVMProcessLock.lock()
        defer { linuxLLVMProcessLock.unlock() }
        return try body()
    }

    private static let linuxLLVMProcessLock = NSLock()

    /// Each `kswiftc` process has private temporary inputs, but concurrent Swift
    /// toolchain invocations can still interfere on self-hosted runners. Keep the
    /// complete link operation serialized per target while retaining private
    /// autolink stub directories.
    static func withLinuxExecutableToolchainLock<T>(
        target: TargetTriple,
        body: () throws -> T
    ) throws -> T {
        guard target.os.hasPrefix("linux") else {
            return try body()
        }

        // Per-user directory so another local user cannot pre-create it. Atomic
        // mkdir(0700) plus the ownership check on EEXIST defeats the TOCTOU/symlink
        // hazard of a shared, world-writable temp directory.
        let lockDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-codegen-locks-\(getuid())", isDirectory: true)
        let mkdirResult = lockDirectory.path.withCString { path in
            mkdir(path, S_IRWXU)
        }
        if mkdirResult != 0 {
            if errno == EEXIST {
                try verifyOwnedDirectory(at: lockDirectory)
            } else {
                throw CodegenCriticalSectionError.systemCallFailed("mkdir", errno)
            }
        }

        let targetKey = CodegenRuntimeSupport.stableFNV1a64Hex(CodegenRuntimeSupport.targetTripleString(target))
        let lockURL = lockDirectory.appendingPathComponent("executable-toolchain-\(targetKey).lock")
        // O_NOFOLLOW rejects a planted symlink at the lock-file path; the fstat
        // check below rejects any pre-existing non-regular / attacker-owned file.
        let descriptor = lockURL.path.withCString { path in
            open(path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            throw CodegenCriticalSectionError.systemCallFailed("open", errno)
        }
        defer { close(descriptor) }

        try verifyOwnedRegularFile(descriptor: descriptor)

        guard flock(descriptor, LOCK_EX) == 0 else {
            throw CodegenCriticalSectionError.systemCallFailed("flock", errno)
        }
        defer { _ = flock(descriptor, LOCK_UN) }

        return try body()
    }

    private static func verifyOwnedDirectory(at url: URL) throws {
        var info = stat()
        let result = url.path.withCString { path in
            lstat(path, &info)
        }
        guard result == 0 else {
            throw CodegenCriticalSectionError.systemCallFailed("lstat", errno)
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR else {
            throw CodegenCriticalSectionError.insecureLockDirectory(url.path)
        }
        guard info.st_uid == getuid() else {
            throw CodegenCriticalSectionError.insecureLockDirectory(url.path)
        }
        guard (info.st_mode & (S_IRWXG | S_IRWXO)) == 0 else {
            throw CodegenCriticalSectionError.insecureLockDirectory(url.path)
        }
    }

    private static func verifyOwnedRegularFile(descriptor: Int32) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            throw CodegenCriticalSectionError.systemCallFailed("fstat", errno)
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            throw CodegenCriticalSectionError.insecureLockFile
        }
        guard info.st_uid == getuid() else {
            throw CodegenCriticalSectionError.insecureLockFile
        }
    }
}

private enum CodegenCriticalSectionError: Error, CustomStringConvertible {
    case systemCallFailed(String, Int32)
    case insecureLockDirectory(String)
    case insecureLockFile

    var description: String {
        switch self {
        case let .systemCallFailed(operation, errorCode):
            return "\(operation) failed: \(String(cString: strerror(errorCode)))"
        case let .insecureLockDirectory(path):
            return "refusing to use lock directory with unexpected ownership or permissions: \(path)"
        case .insecureLockFile:
            return "refusing to use lock file with unexpected type or ownership"
        }
    }
}
