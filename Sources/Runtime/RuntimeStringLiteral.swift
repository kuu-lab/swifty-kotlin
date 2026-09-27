import Foundation

private struct RuntimeWeakLiteralBox {
    weak var box: RuntimeStringBox?
}

/// Only compiler literals and explicit intern() calls enter this pool.
/// Ordinary string construction must retain reference identity for AtomicReference.
private final class RuntimeStringLiteralPool: @unchecked Sendable {
    private let lock = NSLock()
    // Swift String equality normalizes Unicode. Kotlin identity pooling must
    // keep distinct UTF-8/UTF-16 sequences (e.g. composed/decomposed accents).
    private var boxesByBytes: [[UInt8]: RuntimeWeakLiteralBox] = [:]

    func intern(bytes: [UInt8], preferred: RuntimeStringBox? = nil) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if let box = boxesByBytes[bytes]?.box {
            let raw = Int(bitPattern: Unmanaged.passUnretained(box).toOpaque())
            if runtimeStringBox(fromRaw: raw) === box {
                return raw
            }
        }
        let box = preferred ?? RuntimeStringBox(String(decoding: bytes, as: UTF8.self))
        let raw: Int
        let existingRaw = Int(bitPattern: Unmanaged.passUnretained(box).toOpaque())
        if runtimeStringBox(fromRaw: existingRaw) === box {
            raw = existingRaw
        } else {
            raw = registerRuntimeObject(box)
        }
        boxesByBytes[bytes] = RuntimeWeakLiteralBox(box: box)
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
