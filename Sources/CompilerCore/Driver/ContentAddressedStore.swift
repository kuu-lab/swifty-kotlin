import Foundation

/// On-disk store that maps an input hash (the *key*) to an opaque result blob.
///
/// Entries live at `<root>/<key[0..<2]>/<key>` and carry a header with the
/// SHA-256 of the payload, so a torn, truncated or tampered entry is detected
/// on read, removed, and reported as a miss. Callers must always be able to
/// fall back to recomputing; a store failure is never an error.
///
/// Safety properties (same trust rules as `IncrementalCompilationCache`):
/// * the root and shard directories must be owned by the current user and not
///   group/world writable, and are opened without following symlinks;
/// * writes go through a temp file + `renameat`, so readers observe either the
///   old entry or the complete new one;
/// * keys are restricted to lowercase hex, which also rules out path traversal.
public final class ContentAddressedStore: @unchecked Sendable {
    public struct Statistics: Equatable, Sendable {
        public var hits = 0
        public var misses = 0
        public var corrupted = 0
        public var stores = 0
    }

    private static let magic = Data("KSWKCAS1\n".utf8)
    private static let digestLength = 64

    public let rootPath: String
    private let lock = NSLock()
    private var stats = Statistics()

    public init(rootPath: String) {
        self.rootPath = rootPath
    }

    public var statistics: Statistics {
        lock.lock()
        defer { lock.unlock() }
        return stats
    }

    /// Builds a key from labelled parts. Parts are length-prefixed, so
    /// `["ab", "c"]` and `["a", "bc"]` never collide.
    public static func makeKey(parts: [String]) -> String {
        var material = Data()
        for part in parts {
            let bytes = Data(part.utf8)
            material.append(Data("\(bytes.count):".utf8))
            material.append(bytes)
        }
        return FileFingerprint.sha256Hex(material)
    }

    public static func isValidKey(_ key: String) -> Bool {
        key.utf8.count == digestLength && key.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
    }

    /// Returns the payload for `key`, or nil on a miss or a corrupt entry
    /// (which is deleted so the next `store` repairs it).
    public func load(key: String) -> Data? {
        guard Self.isValidKey(key) else { return recordMiss() }
        guard let rootFD = CacheSecurity.openSafeDirectory(at: rootPath, allowCreate: false) else { return recordMiss() }
        defer { close(rootFD) }
        guard let shardFD = CacheSecurity.openSubdirectory(in: rootFD, name: shardName(key), allowCreate: false) else {
            return recordMiss()
        }
        defer { close(shardFD) }

        let fd = openat(shardFD, key, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return recordMiss() }
        var st = stat()
        guard fstat(fd, &st) == 0,
              (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              CacheSecurity.isOwnerAndModeSecure(st: st)
        else {
            close(fd)
            return recordMiss()
        }
        let data = FileHandle(fileDescriptor: fd, closeOnDealloc: true).readDataToEndOfFile()

        let headerLength = Self.magic.count + Self.digestLength + 1
        if data.count >= headerLength,
           data.prefix(Self.magic.count) == Self.magic,
           data[data.startIndex + Self.magic.count + Self.digestLength] == 0x0A
        {
            let digestStart = data.startIndex + Self.magic.count
            let recorded = String(decoding: data[digestStart ..< digestStart + Self.digestLength], as: UTF8.self)
            let payload = Data(data[(data.startIndex + headerLength)...])
            if FileFingerprint.sha256Hex(payload) == recorded {
                lock.lock()
                stats.hits += 1
                lock.unlock()
                return payload
            }
        }
        CacheSecurity.removeEntryIfPresent(in: shardFD, name: key)
        lock.lock()
        stats.corrupted += 1
        stats.misses += 1
        lock.unlock()
        return nil
    }

    /// Stores `payload` under `key`. Returns false (and leaves the store
    /// untouched) if the location is untrusted or the write fails.
    @discardableResult
    public func store(key: String, payload: Data) -> Bool {
        guard Self.isValidKey(key),
              let rootFD = CacheSecurity.openSafeDirectory(at: rootPath, allowCreate: true)
        else { return false }
        defer { close(rootFD) }
        guard let shardFD = CacheSecurity.openSubdirectory(in: rootFD, name: shardName(key), allowCreate: true) else {
            return false
        }
        defer { close(shardFD) }

        var entry = Self.magic
        entry.append(Data(FileFingerprint.sha256Hex(payload).utf8))
        entry.append(0x0A)
        entry.append(payload)
        guard CacheSecurity.writeAtomicFile(in: shardFD, filename: key, data: entry) else { return false }
        lock.lock()
        stats.stores += 1
        lock.unlock()
        return true
    }

    public func contains(key: String) -> Bool {
        guard Self.isValidKey(key),
              let rootFD = CacheSecurity.openSafeDirectory(at: rootPath, allowCreate: false)
        else { return false }
        defer { close(rootFD) }
        guard let shardFD = CacheSecurity.openSubdirectory(in: rootFD, name: shardName(key), allowCreate: false) else {
            return false
        }
        defer { close(shardFD) }
        return faccessat(shardFD, key, F_OK, AT_SYMLINK_NOFOLLOW) == 0
    }

    private func shardName(_ key: String) -> String {
        String(key.prefix(2))
    }

    private func recordMiss() -> Data? {
        lock.lock()
        stats.misses += 1
        lock.unlock()
        return nil
    }
}
