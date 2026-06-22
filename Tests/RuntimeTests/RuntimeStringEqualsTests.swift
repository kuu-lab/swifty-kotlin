// STDLIB-TEXT-FN-016: String.equals(other: String?)
@testable import Runtime
import XCTest

final class RuntimeStringEqualsTests: XCTestCase {
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

    func testEqualsSameContent() {
        XCTAssertTrue(boolValue(kk_string_equals(runtimeString("hello"), runtimeString("hello"))))
    }

    func testEqualsDifferentContent() {
        XCTAssertFalse(boolValue(kk_string_equals(runtimeString("hello"), runtimeString("world"))))
    }

    func testEqualsEmptyStrings() {
        XCTAssertTrue(boolValue(kk_string_equals(runtimeString(""), runtimeString(""))))
    }

    func testEqualsOtherNull() {
        XCTAssertFalse(boolValue(kk_string_equals(runtimeString("hello"), runtimeNullSentinelInt)))
    }

    func testEqualsCaseSensitive() {
        XCTAssertFalse(boolValue(kk_string_equals(runtimeString("abc"), runtimeString("ABC"))))
    }

    func testEqualsUnicode() {
        XCTAssertTrue(boolValue(kk_string_equals(runtimeString("こんにちは"), runtimeString("こんにちは"))))
        XCTAssertFalse(boolValue(kk_string_equals(runtimeString("こんにちは"), runtimeString("さようなら"))))
    }
}
