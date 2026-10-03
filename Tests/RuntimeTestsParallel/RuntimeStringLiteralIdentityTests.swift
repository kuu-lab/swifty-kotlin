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
}
