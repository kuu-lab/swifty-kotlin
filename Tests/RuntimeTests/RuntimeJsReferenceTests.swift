@testable import Runtime
import XCTest

final class RuntimeJsReferenceTests: XCTestCase {
    private func withFlatString<T>(
        _ value: String,
        _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
    ) -> T {
        Array(value.utf8).withUnsafeBufferPointer { buffer in
            body(buffer.baseAddress, value.unicodeScalars.count, value.utf8.count, 0)
        }
    }

    func testJsReferenceGetUnwrapsStoredValue() {
        let valueRaw = kk_box_int(42)
        let referenceRaw = registerRuntimeObject(RuntimeJsReferenceBox(valueRaw: valueRaw))
        XCTAssertEqual(kk_js_reference_get(referenceRaw), valueRaw)
        XCTAssertEqual(kk_unbox_int(kk_js_reference_get(referenceRaw)), 42)
    }

    func testStringToJsStringFlatStoresRuntimeStringValue() throws {
        let raw = withFlatString("hello 🌊") { data, length, byteCount, hash in
            kk_string_toJsString_flat(data, length, byteCount, hash)
        }
        let ptr = try XCTUnwrap(UnsafeMutableRawPointer(bitPattern: raw))
        let box = tryCast(ptr, to: RuntimeJsStringBox.self)
        XCTAssertEqual(box?.value, "hello 🌊")
    }
}
