import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Trust checks for filesystem locations whose contents can end up executing
/// inside the compiler process (an executable found via `$PATH`, or a dynamic
/// library passed to `dlopen`). A location is trusted only when it is owned
/// by `root` or the current user and is not writable by other users. A group
/// write bit is tolerated only when the owning group is an administrative
/// group (`admin`, `wheel`, `root`, `sudo`), whose members can already manage
/// system software or elevate to root — e.g. a standard Homebrew install makes
/// prefix subdirectories like `/opt/homebrew/Cellar` `drwxrwxr-x` owned by the
/// installing user and group `admin`. Every check fails closed: anything that
/// cannot be inspected is treated as untrusted.
package enum TrustedFileSystem {

    /// The outcome of an `inspectLoadableFile` check.
    package enum LoadableFileInspection: Sendable, Equatable {
        /// The canonical absolute path of a file that passed every check.
        case trusted(String)
        /// The first path component that failed a check — the file itself or
        /// the nearest rejecting ancestor directory — and why.
        case rejected(component: String, reason: RejectionReason)
    }

    /// Why a loadable-file candidate was rejected.
    package enum RejectionReason: Sendable, Equatable {
        /// The path was not absolute; relative paths resolve against the
        /// process's CWD, which another local user may influence.
        case notAbsolutePath
        /// No file exists at the path.
        case missing
        /// The path exists but is a directory.
        case notRegularFile
        /// The path is owned by an untrusted user, or writable by others or
        /// by a non-administrative group.
        case unsafeOwnershipOrPermissions

        /// Human-facing explanation for diagnostics (e.g. stderr lines emitted
        /// when a libLLVM candidate is skipped).
        package var diagnosticDetail: String {
            switch self {
            case .notAbsolutePath:
                return "is not an absolute path"
            case .missing:
                return "does not exist"
            case .notRegularFile:
                return "is a directory"
            case .unsafeOwnershipOrPermissions:
                return "is owned by an untrusted user or writable by a non-administrative group"
            }
        }
    }

    /// A directory is trusted only when it exists, is a directory, is not
    /// writable by others or by a non-administrative group, and is owned by
    /// `root` or the current user. This rejects directories another local user
    /// could use to plant a malicious binary.
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
    /// missing or unsafe to load. See `inspectLoadableFile` for the checks
    /// applied.
    package static func trustedLoadableFile(
        _ path: String,
        fileManager: FileManager = .default
    ) -> String? {
        guard case .trusted(let resolvedPath) = inspectLoadableFile(path, fileManager: fileManager) else {
            return nil
        }
        return resolvedPath
    }

    /// Validates a path like `trustedLoadableFile`: it must be absolute, must
    /// exist as a regular file, must be owned by `root` or the current user
    /// and writable only by the owner or an administrative group, and every
    /// ancestor directory must satisfy `isTrustedDirectory`. Unlike
    /// `trustedLoadableFile` the result names the offending component so a
    /// caller can explain why a candidate was skipped.
    package static func inspectLoadableFile(
        _ path: String,
        fileManager: FileManager = .default
    ) -> LoadableFileInspection {
        // A relative path resolves against the process's CWD, which another
        // local user may influence; only absolute paths are considered.
        guard path.hasPrefix("/") else {
            return .rejected(component: path, reason: .notAbsolutePath)
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .rejected(component: path, reason: .missing)
        }
        guard !isDirectory.boolValue else {
            return .rejected(component: path, reason: .notRegularFile)
        }
        let resolvedPath = URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardized
            .path
        guard hasTrustedOwnershipAndPermissions(at: resolvedPath, fileManager: fileManager) else {
            return .rejected(component: resolvedPath, reason: .unsafeOwnershipOrPermissions)
        }
        var directory = URL(fileURLWithPath: resolvedPath).deletingLastPathComponent().path
        while directory.count > 1 {
            guard isTrustedDirectory(directory, fileManager: fileManager) else {
                return .rejected(component: directory, reason: .unsafeOwnershipOrPermissions)
            }
            let parent = URL(fileURLWithPath: directory).deletingLastPathComponent().path
            if parent == directory {
                break
            }
            directory = parent
        }
        return .trusted(resolvedPath)
    }

    /// Ownership and permission check shared by files and directories: not
    /// writable by others, writable by the owning group only when that group
    /// is administrative, and owned by `root` or the current user.
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
        let otherWrite: UInt16 = 0o002
        if permissions & otherWrite != 0 {
            return false
        }
        let groupWrite: UInt16 = 0o020
        if permissions & groupWrite != 0 {
            // A group-writable entry is trusted only when the owning group is
            // administrative: its members can already manage system software
            // or elevate to root, so the write bit grants them nothing new.
            guard let groupName = attributes[.groupOwnerAccountName] as? String,
                  administrativeGroupNames.contains(groupName) else {
                return false
            }
        }
        return owner == 0 || owner == getuid()
    }

    /// Group names treated as administrative for the group-write exception:
    /// `admin` (Homebrew-managed directories on macOS) and the
    /// root-equivalent groups `wheel`, `root`, and `sudo`.
    static let administrativeGroupNames: Set<String> = [
        "admin",
        "root",
        "sudo",
        "wheel",
    ]

    private static func isSymbolicLink(_ path: String, fileManager: FileManager) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: path)) != nil
    }
}
