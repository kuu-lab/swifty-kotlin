// STDLIB-TEXT-FN-016: String.equals(other: String?)
#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeStringEqualsTests {
    private func runtimeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    private func boolValue(_ raw: Int) -> Bool {
        // kk_string_equals returns raw 0/1 (not a boxed Bool); kk_unbox_bool
        // correctly handles both raw integers and RuntimeBoolBox pointers.
        kk_unbox_bool(raw) != 0
    }

    private func withFlatStrings<T>(
        _ lhs: String,
        _ rhs: String,
        _ body: (
            UnsafePointer<UInt8>?, Int, Int, Int,
            UnsafePointer<UInt8>?, Int, Int, Int
        ) -> T
    ) -> T {
        let lhsBytes = Array(lhs.utf8)
        let rhsBytes = Array(rhs.utf8)
        return lhsBytes.withUnsafeBufferPointer { lhsBuffer in
            rhsBytes.withUnsafeBufferPointer { rhsBuffer in
                body(
                    lhsBuffer.baseAddress,
                    lhs.unicodeScalars.count,
                    lhsBytes.count,
                    0,
                    rhsBuffer.baseAddress,
                    rhs.unicodeScalars.count,
                    rhsBytes.count,
                    0
                )
            }
        }
    }

    @Test
    func testEqualsSameContent() {
        #expect(boolValue(kk_string_equals(runtimeString("hello"), runtimeString("hello"))))
    }

    @Test
    func testFlatRoundTripPreservesStringHandleIdentity() {
        let original = runtimeString("atomic-reference")
        var length = 0
        var byteCount = 0
        var hash = 0
        let flatData = kk_string_to_flat(original, &length, &byteCount, &hash)
        let roundTrip = kk_string_from_flat(flatData, length, byteCount, hash)

        #expect(roundTrip == original)
        #expect(roundTrip != runtimeString("atomic-reference"))
    }

    @Test
    func testEqualsDifferentContent() {
        #expect(!boolValue(kk_string_equals(runtimeString("hello"), runtimeString("world"))))
    }

    @Test
    func testEqualsEmptyStrings() {
        #expect(boolValue(kk_string_equals(runtimeString(""), runtimeString(""))))
    }

    @Test
    func testEqualsOtherNull() {
        #expect(!boolValue(kk_string_equals(runtimeString("hello"), runtimeNullSentinelInt)))
    }

    @Test
    func testEqualsCaseSensitive() {
        #expect(!boolValue(kk_string_equals(runtimeString("abc"), runtimeString("ABC"))))
    }

    @Test
    func testEqualsUnicode() {
        #expect(boolValue(kk_string_equals(runtimeString("こんにちは"), runtimeString("こんにちは"))))
        #expect(!boolValue(kk_string_equals(runtimeString("こんにちは"), runtimeString("さようなら"))))
    }

    @Test
    func testEqualsUsesUTF16CodeUnitsInsteadOfCanonicalEquivalence() {
        let composed = runtimeString("é")
        let decomposed = runtimeString("e\u{301}")
        #expect(!boolValue(kk_string_equals(composed, decomposed)))

        withFlatStrings("Å", "Å") { lhsData, lhsLength, lhsByteCount, lhsHash,
                                     rhsData, rhsLength, rhsByteCount, rhsHash in
            #expect(__kk_string_equals_flat(
                lhsData,
                lhsLength,
                lhsByteCount,
                lhsHash,
                rhsData,
                rhsLength,
                rhsByteCount,
                rhsHash
            ) == 0)
        }
    }
}
#endif
