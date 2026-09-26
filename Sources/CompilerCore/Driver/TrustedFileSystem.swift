import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Trust checks for filesystem locations whose contents can end up executing
/// inside the compiler process (an executable found via `$PATH`, or a dynamic
/// library passed to `dlopen`). A location is trusted only when it is owned
/// by `root` or the current user and is not writable by group or others, so
/// another local user cannot plant malicious code where the compiler will run
/// it. Every check fails closed: anything that cannot be inspected is treated
/// as untrusted.
package enum TrustedFileSystem {

    /// A directory is trusted only when it exists, is a directory, is not
    /// writable by group or others, and is owned by `root` or the current
    /// user. This rejects directories another local user could use to plant a
    /// malicious binary.
    package static func isTrustedDirectory(
        _ path: String,
        fileManager: FileManager = .default
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        if isSymbolicLink(path, fileManager: fileManager) {
            let parentPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
            guard parentPath != path, isTrustedDirectory(parentPath, fileManager: fileManager) else {
                return false
            }
        }
        // Resolve symlinks so we inspect the target directory's attributes
        // rather than the link's (symlinks always report 0o777 permissions,
        // e.g. /bin -> /usr/bin on modern Debian/Ubuntu).
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return hasTrustedOwnershipAndPermissions(at: resolvedPath, fileManager: fileManager)
    }

    /// Returns the canonical absolute path of a regular file that may be loaded
    /// into the process (for example via `dlopen`), or `nil` when the file is
    /// missing or unsafe to load. The file must sit on an absolute path, be
    /// owned by `root` or the current user, not be writable by group or
    /// others, and every ancestor directory must satisfy `isTrustedDirectory`.
    package static func trustedLoadableFile(
        _ path: String,
        fileManager: FileManager = .default
    ) -> String? {
        // A relative path resolves against the process's CWD, which another
        // local user may influence; only absolute paths are considered.
        guard path.hasPrefix("/") else {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        let resolvedPath = URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardized
            .path
        guard hasTrustedOwnershipAndPermissions(at: resolvedPath, fileManager: fileManager) else {
            return nil
        }
        var directory = URL(fileURLWithPath: resolvedPath).deletingLastPathComponent().path
        while directory.count > 1 {
            guard isTrustedDirectory(directory, fileManager: fileManager) else {
                return nil
            }
            let parent = URL(fileURLWithPath: directory).deletingLastPathComponent().path
            if parent == directory {
                break
            }
            directory = parent
        }
        return resolvedPath
    }

    /// Ownership and permission check shared by files and directories: not
    /// writable by group or others, and owned by `root` or the current user.
    /// Fails closed when the attributes cannot be determined.
    private static func hasTrustedOwnershipAndPermissions(
        at path: String,
        fileManager: FileManager
    ) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value,
              let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value else {
            return false
        }
        let groupWrite: UInt16 = 0o020
        let otherWrite: UInt16 = 0o002
        if permissions & (groupWrite | otherWrite) != 0 {
            return false
        }
        return owner == 0 || owner == getuid()
    }

    private static func isSymbolicLink(_ path: String, fileManager: FileManager) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: path)) != nil
    }
}
