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

    @Test
    func testEqualsSameContent() {
        #expect(boolValue(kk_string_equals(runtimeString("hello"), runtimeString("hello"))))
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
}
#endif
