import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Trust-boundary enforcement for the incremental compilation cache.
///
/// The cache is a security boundary, not trusted workspace input: a poisoned
/// cache must never be able to substitute attacker-chosen build outputs.
///
/// Two layers are enforced:
/// - Location: a cache directory must be a private, current-user-owned
///   directory — never a symlink and never accessible by group/other. For the
///   managed default location every ancestor inside the per-user cache root
///   is validated the same way.
/// - Integrity: every file read back must match `integrity.json`, a keyed
///   HMAC-SHA256 index written at save time. The MAC key lives in the
///   per-user cache root outside any workspace, so a repository can never
///   carry a self-authenticating cache.
///
/// Anything that fails validation is a cache miss and falls back to a full
/// build.
enum IncrementalCacheTrust {
    /// Outcome of validating a candidate cache directory before reading it.
    enum LocationTrust {
        /// Directory exists and passed every check.
        case trusted
        /// Directory does not exist; nothing to load.
        case missing
        /// Directory failed validation; its contents are ignored entirely.
        case untrusted(String)
    }

    private static let directoryMode: mode_t = 0o700
    private static let keyFileMode: mode_t = 0o600
    static let integrityIndexName = "integrity.json"
    static let integrityKeyName = "incremental-cache.key"

    private static let supportedIndexVersion = 1

    private struct IntegrityIndex: Codable {
        struct Entry: Codable {
            let path: String
            let sha256: String
        }
        let version: Int
        let entries: [Entry]
        let mac: String
    }

    // MARK: - Location validation

    /// Read-only validation used before loading state. A missing cache
    /// directory yields `.missing`; anything unsafe yields `.untrusted` with a
    /// reason suitable for logging.
    static func validateLocation(cachePath: String, managedAncestorBase: String?) -> LocationTrust {
        let fm = FileManager.default
        guard fm.fileExists(atPath: cachePath) else {
            return .missing
        }
        for component in strictComponents(cachePath: cachePath, managedAncestorBase: managedAncestorBase) {
            if let violation = privateDirectoryViolation(at: component) {
                return .untrusted(violation)
            }
        }
        if let base = managedAncestorBase.map(normalize) {
            let parent = parentPath(of: base)
            if parent != base, let violation = sharedDirectoryViolation(at: parent) {
                return .untrusted(violation)
            }
        }
        return .trusted
    }

    /// Ensures the cache location is a private directory, creating missing
    /// components and tightening permissions on components owned by the
    /// current user. Returns false when the location cannot be made safe —
    /// the caller must not write into it.
    static func ensureSecureLocation(cachePath: String, managedAncestorBase: String?) -> Bool {
        let fm = FileManager.default
        if let base = managedAncestorBase.map(normalize) {
            let parent = parentPath(of: base)
            if parent != base {
                if !fm.fileExists(atPath: parent) {
                    try? fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
                }
                if sharedDirectoryViolation(at: parent) != nil {
                    return false
                }
            }
            for component in strictComponents(cachePath: cachePath, managedAncestorBase: base).reversed() {
                if !secureDirectory(at: component) {
                    return false
                }
            }
            return true
        }
        return secureDirectory(at: normalize(cachePath))
    }

    /// Directories that must be private: the cache leaf plus every component
    /// between it and `managedAncestorBase` (inclusive). With no base — an
    /// explicitly configured cache path — only the leaf is checked; the MAC
    /// still authenticates the contents.
    private static func strictComponents(cachePath: String, managedAncestorBase: String?) -> [String] {
        let leaf = normalize(cachePath)
        guard let base = managedAncestorBase.map(normalize) else {
            return [leaf]
        }
        var components: [String] = []
        var cursor = leaf
        while true {
            components.append(cursor)
            if cursor == base {
                return components
            }
            let parent = parentPath(of: cursor)
            if parent == cursor {
                // Climbed past the base — the path is not under the managed
                // root, so only the leaf can be asserted.
                return [leaf]
            }
            cursor = parent
        }
    }

    /// Private directory: owned by the current user, not a symlink, and no
    /// group/other access at all.
    private static func privateDirectoryViolation(at path: String) -> String? {
        guard let info = lstatInfo(path) else {
            return "'\(path)' is missing"
        }
        guard info.isDirectory, !info.isSymlink else {
            return "'\(path)' is a symlink or not a directory"
        }
        guard info.uid == geteuid() else {
            return "'\(path)' is not owned by the current user"
        }
        guard info.mode & 0o077 == 0 else {
            return "'\(path)' grants group/other access"
        }
        return nil
    }

    /// Shared ancestor directory (e.g. the platform caches directory): owned
    /// by the current user, not a symlink, and not writable by group/other.
    private static func sharedDirectoryViolation(at path: String) -> String? {
        guard let info = lstatInfo(path) else {
            return "'\(path)' is missing"
        }
        guard info.isDirectory, !info.isSymlink else {
            return "'\(path)' is a symlink or not a directory"
        }
        guard info.uid == geteuid() else {
            return "'\(path)' is not owned by the current user"
        }
        guard info.mode & 0o022 == 0 else {
            return "'\(path)' is writable by group/other"
        }
        return nil
    }

    /// Creates `path` when missing, then asserts it is a private directory.
    private static func secureDirectory(at path: String) -> Bool {
        let fm = FileManager.default
        if lstatInfo(path) == nil {
            let parent = parentPath(of: path)
            if !parent.isEmpty, parent != path, !fm.fileExists(atPath: parent) {
                try? fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            }
            _ = path.withCString { mkdir($0, directoryMode) }
        }
        guard let info = lstatInfo(path),
              info.isDirectory, !info.isSymlink, info.uid == geteuid()
        else {
            return false
        }
        _ = chmod(path, directoryMode)
        guard let secured = lstatInfo(path) else {
            return false
        }
        return secured.isDirectory && !secured.isSymlink && (secured.mode & 0o077 == 0)
    }

    // MARK: - Integrity index

    /// Loads and authenticates `integrity.json`. Returns nil when the index is
    /// absent, malformed, or fails its keyed MAC — the cache is then ignored.
    static func readIntegrityIndex(cachePath: String) -> [String: String]? {
        guard let key = integrityKey(createIfMissing: false) else {
            return nil
        }
        let indexPath = normalize(cachePath) + "/" + integrityIndexName
        guard let info = lstatInfo(indexPath), info.isRegular,
              let data = try? Data(contentsOf: URL(fileURLWithPath: indexPath)),
              let index = try? JSONDecoder().decode(IntegrityIndex.self, from: data),
              index.version == supportedIndexVersion,
              secureCompare(index.mac, mac(for: index.entries, key: key))
        else {
            return nil
        }
        return Dictionary(uniqueKeysWithValues: index.entries.map { ($0.path, $0.sha256) })
    }

    /// Recomputes the integrity index over every regular file in the cache
    /// directory and writes it atomically. Returns the authenticated digest
    /// map on success, nil when the key cannot be established or the write
    /// fails — the cache must then not be trusted.
    @discardableResult
    static func writeIntegrityIndex(cachePath: String) -> [String: String]? {
        guard let key = integrityKey(createIfMissing: true) else {
            return nil
        }
        let fm = FileManager.default
        let root = normalize(cachePath)
        var entries: [IntegrityIndex.Entry] = []
        if let enumerator = fm.enumerator(atPath: root) {
            for case let rawPath as String in enumerator {
                let relative = normalizeRelativePath(rawPath)
                if relative == integrityIndexName {
                    continue
                }
                let fullPath = root + "/" + relative
                guard let info = lstatInfo(fullPath) else {
                    continue
                }
                // Only regular files are indexed; directories and links are
                // skipped, which also keeps them out of any restored output.
                guard info.isRegular else {
                    continue
                }
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)) else {
                    return nil
                }
                entries.append(IntegrityIndex.Entry(path: relative, sha256: FileFingerprint.sha256Hex(data)))
            }
        }
        entries.sort { $0.path < $1.path }
        let index = IntegrityIndex(
            version: supportedIndexVersion,
            entries: entries,
            mac: mac(for: entries, key: key)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(index) else {
            return nil
        }
        do {
            try data.write(to: URL(fileURLWithPath: root + "/" + integrityIndexName), options: .atomic)
            return Dictionary(uniqueKeysWithValues: index.entries.map { ($0.path, $0.sha256) })
        } catch {
            return nil
        }
    }

    /// Returns the file's contents only when they match the authenticated
    /// index entry for `relativePath`.
    static func authenticatedFileData(
        cachePath: String,
        relativePath: String,
        index: [String: String]
    ) -> Data? {
        guard let expectedDigest = index[relativePath] else {
            return nil
        }
        let fullPath = normalize(cachePath) + "/" + relativePath
        guard let info = lstatInfo(fullPath), info.isRegular,
              let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)),
              FileFingerprint.sha256Hex(data) == expectedDigest
        else {
            return nil
        }
        return data
    }

    /// Re-verifies an output artifact against the authenticated index at
    /// restore time so bytes swapped in after `loadPreviousState` are caught.
    /// A directory artifact must match the index exactly: every file on disk
    /// is authenticated and nothing may be added or removed.
    static func verifyArtifact(
        cachePath: String,
        artifact: CachedOutputArtifact,
        index: [String: String]
    ) -> Bool {
        let root = normalize(cachePath)
        let relative = artifact.relativePath
        switch artifact.kind {
        case .file:
            return authenticatedFileData(cachePath: root, relativePath: relative, index: index) != nil
        case .directory:
            let directoryPath = root + "/" + relative
            guard let info = lstatInfo(directoryPath), info.isDirectory else {
                return false
            }
            var onDisk: Set<String> = []
            guard let enumerator = FileManager.default.enumerator(atPath: directoryPath) else {
                return false
            }
            for case let rawSubPath as String in enumerator {
                let sub = normalizeRelativePath(rawSubPath)
                let fullPath = directoryPath + "/" + sub
                guard let entryInfo = lstatInfo(fullPath) else {
                    return false
                }
                if entryInfo.isDirectory {
                    continue
                }
                // Symlinks or other non-regular files inside a restored
                // directory artifact are rejected outright.
                guard entryInfo.isRegular else {
                    return false
                }
                onDisk.insert(relative + "/" + sub)
            }
            let indexed = Set(index.keys.filter { $0.hasPrefix(relative + "/") })
            guard !indexed.isEmpty, onDisk == indexed else {
                return false
            }
            return indexed.allSatisfy {
                authenticatedFileData(cachePath: root, relativePath: $0, index: index) != nil
            }
        }
    }

    // MARK: - Integrity key

    /// The per-user key used to authenticate cache contents. It lives in the
    /// user's private cache root — outside any workspace — and is only ever
    /// readable by the current user.
    static func integrityKey(createIfMissing: Bool) -> Data? {
        guard let keyPath = integrityKeyFilePath() else {
            return nil
        }
        if let info = lstatInfo(keyPath) {
            guard info.isRegular, !info.isSymlink, info.uid == geteuid() else {
                return nil
            }
            // Tighten a key created before permission enforcement rather than
            // leaving the cache unusable.
            _ = chmod(keyPath, keyFileMode)
            guard let secured = lstatInfo(keyPath), secured.mode & 0o077 == 0,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: keyPath)),
                  data.count >= 32
            else {
                return nil
            }
            return data
        }
        guard createIfMissing else {
            return nil
        }
        let root = parentPath(of: keyPath)
        guard ensureSecureLocation(cachePath: root, managedAncestorBase: root) else {
            return nil
        }
        var generator = SystemRandomNumberGenerator()
        let key = Data((0 ..< 32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        // O_EXCL avoids clobbering a key created concurrently; the loser reads
        // the winner's key so every cache shares one MAC key.
        let descriptor = keyPath.withCString {
            open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, keyFileMode)
        }
        if descriptor >= 0 {
            defer { close(descriptor) }
            let written = key.withUnsafeBytes { pointer in
                pointer.baseAddress.map { write(descriptor, $0, pointer.count) } ?? -1
            }
            guard written == key.count else {
                return nil
            }
            return key
        }
        if errno == EEXIST {
            return integrityKey(createIfMissing: false)
        }
        return nil
    }

    private static func integrityKeyFilePath() -> String? {
        IncrementalCompilationCache
            .userPrivateCacheBase(allowOverride: false)
            .map { normalize($0) + "/" + integrityKeyName }
    }

    // MARK: - Crypto helpers

    private static func mac(for entries: [IntegrityIndex.Entry], key: Data) -> String {
        struct MACPayload: Codable {
            let version: Int
            let entries: [IntegrityIndex.Entry]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = (try? encoder.encode(
            MACPayload(version: supportedIndexVersion, entries: entries)
        )) ?? Data()
        return hmacSHA256Hex(key: key, message: payload)
    }

    private static func hmacSHA256Hex(key: Data, message: Data) -> String {
        let blockSize = 64
        var keyBytes = [UInt8](key)
        if keyBytes.count > blockSize {
            keyBytes = FileFingerprint.sha256Bytes(Data(keyBytes))
        }
        if keyBytes.count < blockSize {
            keyBytes.append(contentsOf: [UInt8](repeating: 0, count: blockSize - keyBytes.count))
        }
        var inner = [UInt8](repeating: 0x36, count: blockSize)
        var outer = [UInt8](repeating: 0x5C, count: blockSize)
        for i in 0 ..< blockSize {
            inner[i] ^= keyBytes[i]
            outer[i] ^= keyBytes[i]
        }
        inner.append(contentsOf: message)
        outer.append(contentsOf: FileFingerprint.sha256Bytes(Data(inner)))
        return FileFingerprint.sha256Bytes(Data(outer))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func secureCompare(_ a: String, _ b: String) -> Bool {
        var difference = a.utf8.count ^ b.utf8.count
        for (x, y) in zip(a.utf8, b.utf8) {
            difference |= Int(x ^ y)
        }
        return difference == 0
    }

    // MARK: - Path helpers

    static func normalize(_ path: String) -> String {
        var standardized = URL(fileURLWithPath: path).standardized.path
        while standardized.count > 1, standardized.hasSuffix("/") {
            standardized.removeLast()
        }
        return standardized
    }

    private static func normalizeRelativePath(_ path: String) -> String {
        var relative = path
        while relative.hasPrefix("./") {
            relative.removeFirst(2)
        }
        return relative
    }

    private static func parentPath(of path: String) -> String {
        URL(fileURLWithPath: normalize(path)).deletingLastPathComponent().path
    }

    private static func lstatInfo(
        _ path: String
    ) -> (isDirectory: Bool, isSymlink: Bool, isRegular: Bool, uid: uid_t, mode: mode_t)? {
        var info = stat()
        guard path.withCString({ lstat($0, &info) }) == 0 else {
            return nil
        }
        return (
            isDirectory: (info.st_mode & S_IFMT) == S_IFDIR,
            isSymlink: (info.st_mode & S_IFMT) == S_IFLNK,
            isRegular: (info.st_mode & S_IFMT) == S_IFREG,
            uid: info.st_uid,
            mode: info.st_mode
        )
    }
}
