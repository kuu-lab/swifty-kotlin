import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import CompilerCore

enum CodegenCriticalSection {
    static func withLinuxExecutableToolchainLock<T>(
        target: TargetTriple,
        body: () throws -> T
    ) throws -> T {
        guard target.os.hasPrefix("linux") else {
            return try body()
        }

        // Isolate the lock directory per-user so it cannot be pre-created by
        // another local user. Create it atomically with mkdir(0700); if it
        // already exists, verify it is a directory we own with 0700
        // permissions before trusting it. This defeats the TOCTOU/symlink
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

    /// Verifies the given path is a real directory (not a symlink) owned by the
    /// current effective user with no group/other permission bits.
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

    /// Verifies the opened descriptor refers to a regular file owned by the
    /// current effective user, rejecting attacker-controlled inodes.
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
