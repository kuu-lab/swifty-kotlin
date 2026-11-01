#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

private final class CapturedIDBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(String, InternedString)] = []

    func append(contentsOf ids: [(String, InternedString)]) {
        lock.lock()
        storage.append(contentsOf: ids)
        lock.unlock()
    }

    func snapshot() -> [(String, InternedString)] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@Suite
struct StringInternerTests {
    // MARK: - InternedString

    @Test func testInternedStringInvalidAndDefault() {
        #expect(InternedString.invalid.rawValue == -1)
        #expect(InternedString() == InternedString.invalid)
    }

    @Test func testInternedStringHashable() {
        let a = InternedString(rawValue: 1)
        let b = InternedString(rawValue: 1)
        let c = InternedString(rawValue: 2)
        #expect(a == b)
        #expect(a != c)

        #expect(Set([a, b]).count == 1)
        #expect(Set([a, b, c]).count == 2)
    }

    // MARK: - StringInterner basic operations

    @Test func testInternReturnsSameIDForSameString() {
        let interner = StringInterner()
        let id1 = interner.intern("hello")
        let id2 = interner.intern("hello")
        #expect(id1 == id2)
    }

    @Test func testInternReturnsDifferentIDForDifferentStrings() {
        let interner = StringInterner()
        let id1 = interner.intern("hello")
        let id2 = interner.intern("world")
        #expect(id1 != id2)
    }

    @Test func testInternQualifiedNameMatchesComponentInterning() {
        let interner = StringInterner()
        let first = interner.internQualifiedName("pkg.Outer.member")
        let second = interner.internQualifiedName("pkg.Other.member")

        #expect(first.map(interner.resolve) == ["pkg", "Outer", "member"])
        #expect(second.map(interner.resolve) == ["pkg", "Other", "member"])
        #expect(first[0] == second[0])
        #expect(first[2] == second[2])
        #expect(interner.internQualifiedName(".pkg..Outer.").map(interner.resolve) == ["pkg", "Outer"])
    }

    @Test func testResolveReturnsOriginalString() {
        let interner = StringInterner()
        let id = interner.intern("test string")
        let resolved = interner.resolve(id)
        #expect(resolved == "test string")
    }

    @Test func testResolveInvalidIDReturnsEmpty() {
        let interner = StringInterner()
        let result = interner.resolve(InternedString.invalid)
        #expect(result == "")
    }

    @Test func testResolveOutOfBoundsReturnsEmpty() {
        let interner = StringInterner()
        let result = interner.resolve(InternedString(rawValue: 9999))
        #expect(result == "")
    }

    @Test func testInternEmptyString() {
        let interner = StringInterner()
        let id = interner.intern("")
        let resolved = interner.resolve(id)
        #expect(resolved == "")
    }

    @Test func testInternMultipleStrings() {
        let interner = StringInterner()
        let words = ["apple", "banana", "cherry", "date", "elderberry"]
        let ids = words.map(interner.intern)
        #expect(Set(ids).count == words.count)
        #expect(ids.map(interner.resolve) == words)
    }

    @Test func testInternIDsAreMonotonicallyIncreasing() {
        let interner = StringInterner()
        let id0 = interner.intern("a")
        let id1 = interner.intern("b")
        let id2 = interner.intern("c")
        #expect(id0 != InternedString.invalid)
        // strict monotonicity also gives pairwise distinctness
        #expect(id0.rawValue < id1.rawValue)
        #expect(id1.rawValue < id2.rawValue)
    }

    @Test func testInternUnicodeStrings() {
        let interner = StringInterner()
        let japanese = "日本語"
        let emoji = "emoji 🎉"
        let id1 = interner.intern(japanese)
        let id2 = interner.intern(emoji)
        let id3 = interner.intern(japanese)
        #expect(id1 == id3)
        #expect(id1 != id2)
        #expect(interner.resolve(id1) == japanese)
        #expect(interner.resolve(id2) == emoji)
    }

    @Test func testInternDistinguishesCanonicallyEquivalentUTF16Sequences() {
        let interner = StringInterner()
        let decomposed = "e\u{301}"
        let composed = "\u{00E9}"
        let decomposedID = interner.intern(decomposed)
        let composedID = interner.intern(composed)

        #expect(decomposedID != composedID)
        #expect(Array(interner.resolve(decomposedID).utf16) == Array(decomposed.utf16))
        #expect(Array(interner.resolve(composedID).utf16) == Array(composed.utf16))
    }

    @Test func testInternSpecialCharacters() {
        let interner = StringInterner()
        let input = "hello\nworld\ttab"
        let id = interner.intern(input)
        #expect(interner.resolve(id) == input)
    }

    // MARK: - Thread safety

    /// Runs `body` for 10 concurrent iterations and returns once all finish.
    ///
    /// `concurrentPerform` also runs iterations on the calling thread, so it
    /// makes progress even when parallel tests have saturated the global
    /// pool; enqueuing `DispatchQueue.global()` tasks and waiting with a
    /// timeout starved there and timed out under heavy machine load.
    private func runConcurrently(_ body: @escaping @Sendable (Int) -> Void) {
        DispatchQueue.concurrentPerform(iterations: 10, execute: body)
    }

    @Test func testConcurrentInternDoesNotCrash() {
        let interner = StringInterner()

        // Capture IDs returned during the concurrent phase so we verify
        // the actual values produced under contention, not re-interned ones.
        let capturedIDs = CapturedIDBuffer()

        runConcurrently { task in
            capturedIDs.append(contentsOf: (0 ..< 100).map { index in
                let string = "string_\(task)_\(index)"
                return (string, interner.intern(string))
            })
        }

        for (string, id) in capturedIDs.snapshot() {
            #expect(interner.resolve(id) == string)
        }
    }

    @Test func testConcurrentResolveDoesNotCrash() {
        let interner = StringInterner()
        let ids: [InternedString] = (0 ..< 100).map { interner.intern("value_\($0)") }
        let expected: [String] = (0 ..< 100).map { "value_\($0)" }

        // Resolving concurrently must return the same strings as a serial read.
        let mismatches = CapturedIDBuffer()
        runConcurrently { _ in
            let resolved = ids.map(interner.resolve)
            if resolved != expected {
                mismatches.append(contentsOf: zip(resolved, ids).map { ($0, $1) })
            }
        }
        #expect(mismatches.snapshot().isEmpty)
    }
}
#endif
