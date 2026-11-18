import Foundation

#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#else
import CSHA256
#endif

/// The content hash is the comparison key; mtime is retained as diagnostic
/// metadata and for future cache optimizations.
public struct FileFingerprint: Equatable, Codable {
    public let path: String

    public let contentHash: String

    /// Last-modified time as nanoseconds since the Unix epoch.
    /// Stored as `Int64` to avoid floating-point round-trip issues through JSON.
    public let mtimeNanos: Int64

    public init(path: String, contentHash: String, mtimeNanos: Int64) {
        self.path = path
        self.contentHash = contentHash
        self.mtimeNanos = mtimeNanos
    }

    public static func compute(for path: String) -> FileFingerprint? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return compute(for: path, contents: data)
    }

    public static func compute(for path: String, contents: Data) -> FileFingerprint {
        let hash = sha256Hex(contents)
        let mtimeNanos = fileMtimeNanos(path: path)
        return FileFingerprint(path: path, contentHash: hash, mtimeNanos: mtimeNanos)
    }

    public func contentChanged(from other: FileFingerprint) -> Bool {
        contentHash != other.contentHash
    }

    static func sha256Hex(_ data: Data) -> String {
        sha256Bytes(data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Bytes(_ data: Data) -> [UInt8] {
#if canImport(CryptoKit) || canImport(Crypto)
        return Array(SHA256.hash(data: data))
#else
        // The C implementation keeps debug builds fast enough to hash
        // artifact-sized inputs (the bundled stdlib `.kklib` is ~1 GB).
        var digest = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buffer in
            kswiftk_sha256(
                buffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                buffer.count,
                &digest
            )
        }
        return digest
#endif
    }

    private static func fileMtimeNanos(path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date
        else {
            return 0
        }
        // Convert to nanoseconds to avoid floating-point round-trip issues.
        return Int64(date.timeIntervalSince1970 * 1_000_000_000)
    }
}
