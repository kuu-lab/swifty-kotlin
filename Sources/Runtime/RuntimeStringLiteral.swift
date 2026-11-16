import Foundation

private struct RuntimeWeakLiteralBox {
    weak let box: RuntimeStringBox?
}

/// KUU-4591: `Dictionary<[UInt8], _>` hashes element-by-element
/// (`Hasher._combine(UInt8)` per byte), which dominated startup interning.
/// Bulk-feeding the bytes through `Hasher.combine(bytes:)` keeps the same
/// byte-equality semantics at a fraction of the hash cost.
private struct LiteralByteKey: Hashable {
    let bytes: [UInt8]

    static func == (lhs: LiteralByteKey, rhs: LiteralByteKey) -> Bool {
        lhs.bytes == rhs.bytes
    }

    func hash(into hasher: inout Hasher) {
        bytes.withUnsafeBytes { hasher.combine(bytes: $0) }
    }
}

/// Only compiler literals and explicit intern() calls enter this pool.
/// Ordinary string construction must retain reference identity for AtomicReference.
final class RuntimeStringLiteralPool: @unchecked Sendable {
    private let lock = NSLock()
    // Swift String equality normalizes Unicode. Kotlin identity pooling must
    // keep distinct UTF-8/UTF-16 sequences (e.g. composed/decomposed accents).
    private var boxesByBytes: [LiteralByteKey: RuntimeWeakLiteralBox] = [:]
    private var insertionsUntilPruning = 64

    @discardableResult
    func pruneReleasedEntries() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return pruneReleasedEntriesWhileLocked()
    }

    private func pruneReleasedEntriesWhileLocked() -> Int {
        let previousCount = boxesByBytes.count
        boxesByBytes = boxesByBytes.filter { _, entry in
            guard let box = entry.box else { return false }
            let raw = Int(bitPattern: Unmanaged.passUnretained(box).toOpaque())
            return runtimeStringBox(fromRaw: raw) === box
        }
        // Pay for the next full scan with at least one insertion per retained
        // entry. Live startup literals then trigger geometrically spaced scans,
        // while the floor keeps small pools from scanning on every insertion.
        insertionsUntilPruning = max(64, boxesByBytes.count)
        return previousCount - boxesByBytes.count
    }

    func intern(bytes: [UInt8], preferred: RuntimeStringBox? = nil) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let key = LiteralByteKey(bytes: bytes)
        if let box = boxesByBytes[key]?.box {
            let raw = Int(bitPattern: Unmanaged.passUnretained(box).toOpaque())
            if runtimeStringBox(fromRaw: raw) === box {
                return raw
            }
        }
        // Weak values alone would retain the byte-array keys indefinitely.
        // Periodically remove both entries and keys after their object dies or
        // is explicitly released from the runtime registry.
        insertionsUntilPruning -= 1
        if insertionsUntilPruning == 0 {
            _ = pruneReleasedEntriesWhileLocked()
        }
        let box = preferred ?? RuntimeStringBox(String(decoding: bytes, as: UTF8.self))
        let raw: Int
        let existingRaw = Int(bitPattern: Unmanaged.passUnretained(box).toOpaque())
        if runtimeStringBox(fromRaw: existingRaw) === box {
            raw = existingRaw
        } else {
            raw = registerRuntimeObject(box)
        }
        boxesByBytes[key] = RuntimeWeakLiteralBox(box: box)
        return raw
    }
}

private let runtimeStringLiteralPool = RuntimeStringLiteralPool()

// Compiler allocation primitive: all modules use the same literal identity.
@_cdecl("__kk_string_literal_from_utf8")
public func __kk_string_literal_from_utf8(_ pointer: UnsafePointer<UInt8>, _ count: Int) -> Int {
    let bytes = Array(UnsafeBufferPointer(start: pointer, count: max(0, count)))
    return runtimeStringLiteralPool.intern(bytes: bytes)
}

func runtimeInternString(_ raw: Int) -> Int {
    guard let box = runtimeStringBox(fromRaw: raw) else { return raw }
    return runtimeStringLiteralPool.intern(bytes: Array(box.value.utf8), preferred: box)
}
