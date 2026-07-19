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

    @Test func testInternedStringWithRawValue() {
        let s = InternedString(rawValue: 42)
        #expect(s.rawValue == 42)
    }

    @Test func testInternedStringHashable() {
        let a = InternedString(rawValue: 1)
        let b = InternedString(rawValue: 1)
        let c = InternedString(rawValue: 2)
        #expect(a == b)
        #expect(a != c)

        var set = Set<InternedString>()
        set.insert(a)
        set.insert(b)
        #expect(set.count == 1)
        set.insert(c)
        #expect(set.count == 2)
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
        var ids: [InternedString] = []
        for word in words {
            ids.append(interner.intern(word))
        }
        #expect(Set(ids).count == words.count)
        for (i, word) in words.enumerated() {
            #expect(interner.resolve(ids[i]) == word)
        }
    }

    @Test func testInternIDsAreMonotonicallyIncreasing() {
        let interner = StringInterner()
        let id0 = interner.intern("a")
        let id1 = interner.intern("b")
        let id2 = interner.intern("c")
        #expect(id0 != InternedString.invalid)
        #expect(id1 != InternedString.invalid)
        #expect(id2 != InternedString.invalid)
        #expect(id0 != id1)
        #expect(id1 != id2)
        #expect(id0 != id2)
        #expect(id0.rawValue < id1.rawValue)
        #expect(id1.rawValue < id2.rawValue)
    }

    @Test func testInternUnicodeStrings() {
        let interner = StringInterner()
        let id1 = interner.intern("日本語")
        let id2 = interner.intern("emoji 🎉")
        let id3 = interner.intern("日本語")
        #expect(id1 == id3)
        #expect(id1 != id2)
        #expect(interner.resolve(id1) == "日本語")
        #expect(interner.resolve(id2) == "emoji 🎉")
    }

    @Test func testInternSpecialCharacters() {
        let interner = StringInterner()
        let id = interner.intern("hello\nworld\ttab")
        #expect(interner.resolve(id) == "hello\nworld\ttab")
    }

    // MARK: - Thread safety

    @Test func testConcurrentInternDoesNotCrash() {
        let interner = StringInterner()
        let group = DispatchGroup()

        // Capture IDs returned during concurrent phase so we verify
        // the actual values produced under contention, not re-interned ones.
        let capturedIDs = CapturedIDBuffer()

        for i in 0 ..< 10 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                var localIDs: [(String, InternedString)] = []
                for j in 0 ..< 100 {
                    let str = "string_\(i)_\(j)"
                    let id = interner.intern(str)
                    localIDs.append((str, id))
                }
                capturedIDs.append(contentsOf: localIDs)
            }
        }

        #expect(group.wait(timeout: .now() + .seconds(10)) == .success, "Concurrent intern timed out")

        // Verify IDs captured during the concurrent phase resolve correctly
        for (str, id) in capturedIDs.snapshot() {
            #expect(interner.resolve(id) == str)
        }
    }

    @Test func testConcurrentResolveDoesNotCrash() {
        let interner = StringInterner()
        let ids: [InternedString] = (0 ..< 100).map { interner.intern("value_\($0)") }

        let group = DispatchGroup()

        for _ in 0 ..< 10 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                for id in ids {
                    _ = interner.resolve(id)
                }
            }
        }

        #expect(group.wait(timeout: .now() + .seconds(10)) == .success, "Concurrent resolve timed out")
    }
}
#endif
