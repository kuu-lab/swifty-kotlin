#if canImport(Testing)
@testable import Runtime
import Testing
import Foundation

/// KUU-815: flat String buffers used to be pinned forever by a strong
/// process-global registry with no release path. Storages are now managed
/// runtime objects (`objectPointers` + `kk_flat_string_release`), the index
/// only weakly references them, and the raw↔flat bridges deduplicate instead
/// of accumulating a fresh buffer/box per call.
@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeFlatStringOwnershipTests {
    private func toFlat(
        _ raw: Int
    ) -> (data: UnsafeMutablePointer<UInt8>?, length: Int, byteCount: Int, hash: Int) {
        var length = 0
        var byteCount = 0
        var hash = 0
        let data = kk_string_to_flat(raw, &length, &byteCount, &hash)
        return (data, length, byteCount, hash)
    }

    private func registerFlat(
        _ value: String
    ) -> (data: UnsafePointer<UInt8>?, length: Int, byteCount: Int, hash: Int) {
        var length = 0
        var byteCount = 0
        var hash = 0
        let data = runtimeRegisterFlatString(
            value,
            outLength: &length,
            outByteCount: &byteCount,
            outHash: &hash
        )
        return (data.map { UnsafePointer($0) }, length, byteCount, hash)
    }

    @Test func toFlatReusesOneBufferPerStringBox() {
        let raw = runtimeMakeStringRaw("kuu-815-to-flat")
        let before = runtimeFlatStringLiveStorageCountForTesting()

        let first = toFlat(raw)
        let second = toFlat(raw)

        #expect(first.data != nil)
        #expect(first.data == second.data)
        #expect(first.length == second.length)
        #expect(first.byteCount == second.byteCount)
        #expect(runtimeFlatStringLiveStorageCountForTesting() == before + 1)
    }

    @Test func fromFlatDeduplicatesToCanonicalBox() {
        let flat = registerFlat("kuu-815-from-flat")

        let firstRaw = kk_string_from_flat(flat.data, flat.length, flat.byteCount, flat.hash)
        let secondRaw = kk_string_from_flat(flat.data, flat.length, flat.byteCount, flat.hash)

        #expect(firstRaw != 0)
        #expect(firstRaw == secondRaw)
        #expect(runtimeStringFromRaw(firstRaw) == "kuu-815-from-flat")
    }

    @Test func flatRawRoundTripResolvesToOriginBox() {
        let raw = runtimeMakeStringRaw("kuu-815-round-trip")
        let flat = toFlat(raw)

        let bridgedRaw = kk_string_from_flat(
            flat.data.map { UnsafePointer($0) },
            flat.length,
            flat.byteCount,
            flat.hash
        )

        #expect(bridgedRaw == raw)
    }

    @Test func flatStringReleaseFreesAndIsIdempotent() {
        let flat = registerFlat("kuu-815-release")
        let before = runtimeFlatStringLiveStorageCountForTesting()

        #expect(kk_flat_string_release(flat.data) == 1)
        #expect(runtimeFlatStringLiveStorageCountForTesting() == before - 1)
        #expect(runtimeFlatStringRegisteredUTF16CodeUnits(data: flat.data) == nil)

        // Stale pointers after release are safe no-ops.
        #expect(kk_flat_string_release(flat.data) == 0)
        #expect(kk_flat_string_release(nil) == 0)
    }

    @Test func releaseOnLiteralBufferIsANoOp() {
        // A foreign pointer (not produced by the flat registry) must never be
        // released: literals are static memory the runtime does not own.
        var literalBytes = Array("literal".utf8)
        let released = literalBytes.withUnsafeBufferPointer { buffer in
            kk_flat_string_release(buffer.baseAddress)
        }
        #expect(released == 0)
    }

    @Test func releasedFlatBufferIsRecreatedOnNextBridge() {
        let raw = runtimeMakeStringRaw("kuu-815-recreate")
        let first = toFlat(raw)
        #expect(kk_flat_string_release(first.data.map { UnsafePointer($0) }) == 1)

        let second = toFlat(raw)

        #expect(second.data != nil)
        #expect(second.length == first.length)
        #expect(second.byteCount == first.byteCount)
        #expect(runtimeStringFromFlatFields(
            data: second.data.map { UnsafePointer($0) },
            length: second.length,
            byteCount: second.byteCount,
            hash: second.hash
        ) == "kuu-815-recreate")
    }

    @Test func registerFlatStringResultSharesBoxStorage() {
        let raw = runtimeMakeStringRaw("kuu-815-result")

        var firstLength = 0
        var firstByteCount = 0
        var firstHash = 0
        let firstData = runtimeRegisterFlatStringResult(
            raw,
            outLength: &firstLength,
            outByteCount: &firstByteCount,
            outHash: &firstHash
        )

        var secondLength = 0
        var secondByteCount = 0
        var secondHash = 0
        let secondData = runtimeRegisterFlatStringResult(
            raw,
            outLength: &secondLength,
            outByteCount: &secondByteCount,
            outHash: &secondHash
        )

        #expect(firstData != nil)
        #expect(firstData == secondData)
        #expect(firstByteCount == secondByteCount)
    }

    @Test func releasedStorageStillResolvesItsCanonicalBox() {
        // The canonical box is an independent managed handle: releasing the
        // flat buffer does not invalidate a raw obtained earlier.
        let raw = runtimeMakeStringRaw("kuu-815-canonical-after-release")
        let flat = toFlat(raw)
        let bridgedRaw = kk_string_from_flat(
            flat.data.map { UnsafePointer($0) },
            flat.length,
            flat.byteCount,
            flat.hash
        )

        #expect(kk_flat_string_release(flat.data.map { UnsafePointer($0) }) == 1)
        #expect(runtimeStringFromRaw(bridgedRaw) == "kuu-815-canonical-after-release")
    }
}
#endif
