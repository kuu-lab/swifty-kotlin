@testable import Runtime
import Testing

@Suite
struct RuntimeStringLiteralIdentityTests {
    private func literal(_ text: String) -> Int {
        Array(text.utf8).withUnsafeBufferPointer { bytes in
            __kk_string_literal_from_utf8(bytes.baseAddress!, bytes.count)
        }
    }

    @Test
    func equalLiteralBuffersShareIdentityAndDynamicStringsStayDistinct() {
        let first = literal("literal-identity")
        let second = literal("literal-identity")
        #expect(first == second)
        let dynamic = Array("literal-identity".utf8).withUnsafeBufferPointer { bytes in
            Int(bitPattern: kk_string_from_utf8(bytes.baseAddress!, Int32(bytes.count)))
        }
        #expect(dynamic != first)
        #expect(__kk_string_intern(dynamic) == first)
    }

    @Test
    func unicodeNormalizationDoesNotMergeDistinctLiterals() {
        #expect(literal("\u{00e9}") != literal("e\u{0301}"))
    }

    @Test
    func poolRecoversAfterExplicitObjectRelease() {
        let original = literal("released-literal-identity")
        #expect(runtimeReleaseObject(original))
        let replacement = literal("released-literal-identity")
        #expect(runtimeStringBox(fromRaw: replacement)?.value == "released-literal-identity")
        #expect(literal("released-literal-identity") == replacement)
    }

    @Test
    func releasedObjectsDoNotLeavePermanentPoolKeys() {
        let pool = RuntimeStringLiteralPool()
        let handles = (0 ..< 128).map { index in
            pool.intern(bytes: Array("released-pool-key-\(index)".utf8))
        }
        // All entries remain valid while their runtime objects are registered.
        #expect(pool.pruneReleasedEntries() == 0)
        for handle in handles {
            #expect(runtimeReleaseObject(handle))
        }
        #expect(pool.pruneReleasedEntries() == handles.count)
        #expect(pool.pruneReleasedEntries() == 0)
    }

    @Test
    func largeLivePoolDoesNotPruneAfterOnly64Insertions() {
        let pool = RuntimeStringLiteralPool()
        var handles = (0 ..< 4096).map { index in
            pool.intern(bytes: Array("large-live-pool-\(index)".utf8))
        }
        defer {
            for handle in handles {
                runtimeReleaseObject(handle)
            }
        }
        #expect(pool.pruneReleasedEntries() == 0)
        #expect(runtimeReleaseObject(handles.removeLast()))

        for index in 0 ..< 64 {
            handles.append(pool.intern(bytes: Array("large-live-pool-new-\(index)".utf8)))
        }
        // A fixed 64-insertion cadence would already have removed this key.
        #expect(pool.pruneReleasedEntries() == 1)
        for index in 0 ..< 4095 {
            #expect(pool.intern(bytes: Array("large-live-pool-\(index)".utf8)) == handles[index])
        }
    }

    @Test
    func automaticPruningRemovesReleasedKeysAfterPoolSizedBatch() {
        let pool = RuntimeStringLiteralPool()
        let count = 512
        var handles = (0 ..< count).map { index in
            pool.intern(bytes: Array("automatic-prune-old-\(index)".utf8))
        }
        defer {
            for handle in handles {
                runtimeReleaseObject(handle)
            }
        }
        #expect(pool.pruneReleasedEntries() == 0)
        // Keep the weak references alive to also exercise registry validation.
        let releasedBoxes = handles.compactMap { runtimeStringBox(fromRaw: $0) }
        #expect(releasedBoxes.count == count)
        for handle in handles {
            #expect(runtimeReleaseObject(handle))
        }
        handles.removeAll()

        withExtendedLifetime(releasedBoxes) {
            for index in 0 ..< count {
                handles.append(pool.intern(bytes: Array("automatic-prune-new-\(index)".utf8)))
            }
            // Automatic pruning must have removed all the unregistered keys.
            #expect(pool.pruneReleasedEntries() == 0)
            for index in 0 ..< count {
                #expect(pool.intern(bytes: Array("automatic-prune-new-\(index)".utf8)) == handles[index])
            }
        }
    }
}
