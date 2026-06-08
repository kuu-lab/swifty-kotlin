@testable import Runtime
import XCTest

final class RuntimeStringBuilderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // STDLIB-TEXT-FN-024: insert
    func testInsertObjInsertsValueAtIndexAndReturnsReceiver() {
        let builder = makeBuilder("ac")
        let value = makeRuntimeString("b")
        var thrown = 0

        let returned = kk_string_builder_insert_obj(builder, 1, value, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abc")
    }

    func testAppendRangeAppendsSubstringSliceAndReturnsReceiver() {
        let builder = makeBuilder("hello")
        let returned = withFlatString("WORLD") { data, length, byteCount, hash in
            kk_string_builder_appendRange_obj_flat(builder, data, length, byteCount, hash, 1, 4)
        }

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "helloORL")
    }

    func testAppendRangeFromEmptyRangeAppendsNothing() {
        let builder = makeBuilder("abc")
        let returned = withFlatString("XYZ") { data, length, byteCount, hash in
            kk_string_builder_appendRange_obj_flat(builder, data, length, byteCount, hash, 2, 2)
        }

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abc")
    }

    func testInsertObjAtBeginningPrependsValue() {
        let builder = makeBuilder("bc")
        let value = makeRuntimeString("a")
        var thrown = 0

        _ = kk_string_builder_insert_obj(builder, 0, value, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abc")
    }

    func testInsertObjAtEndAppendsValue() {
        let builder = makeBuilder("ab")
        let value = makeRuntimeString("c")
        var thrown = 0

        _ = kk_string_builder_insert_obj(builder, 2, value, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abc")
    }

    func testDeleteAtRemovesCharacterAndReturnsReceiver() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("abc"))
        var thrown = 0

        let returned = kk_string_builder_deleteAt(builder, 1, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "ac")
    }

    func testDeleteRangeRemovesRangeAndReturnsReceiver() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("abcdef"))
        var thrown = 0

        let returned = kk_string_builder_deleteRange(builder, 1, 4, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "aef")
    }

    func testInsertRangeInsertsValueSliceAndReturnsReceiver() {
        let builder = makeBuilder("ab")
        let value = makeRuntimeString("WXYZ")
        var thrown = 0

        let returned = kk_string_builder_insertRange_obj(builder, 1, value, 1, 3, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "aXYb")
    }

    func testSetRangeReplacesRangeAndReturnsReceiver() {
        let builder = makeBuilder("abcd")
        let value = makeRuntimeString("XYZ")
        var thrown = 0

        let returned = kk_string_builder_setRange(builder, 1, 3, value, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "aXYZd")
    }

    // STDLIB-TEXT-FN-064: operator fun set(index, value) — backed by kk_string_builder_setCharAt
    func testSetCharAtReplacesCharacterAtIndex() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("abc"))
        var thrown = 0

        let returned = kk_string_builder_setCharAt(
            builder,
            1,
            kk_box_char(Int(Unicode.Scalar("X").value)),
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "aXc")
    }

    func testSetCharAtFirstIndexReplacesCharacter() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("hello"))
        var thrown = 0

        _ = kk_string_builder_setCharAt(
            builder,
            0,
            kk_box_char(Int(Unicode.Scalar("H").value)),
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "Hello")
    }

    func testFlatStringBuilderAPIsUseFlattenedStringFields() {
        let builder = withFlatString("ac") { data, length, byteCount, hash in
            kk_string_builder_new_from_string_flat(data, length, byteCount, hash)
        }

        let insertReturned = withFlatString("b") { data, length, byteCount, hash in
            kk_string_builder_insert_obj_flat(builder, 1, data, length, byteCount, hash)
        }
        XCTAssertEqual(insertReturned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abc")

        let appendReturned = withFlatString("D") { data, length, byteCount, hash in
            kk_string_builder_append_obj_flat(builder, data, length, byteCount, hash)
        }
        XCTAssertEqual(appendReturned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abcD")

        let appendLineReturned = withFlatString("E") { data, length, byteCount, hash in
            kk_string_builder_append_line_obj_flat(builder, data, length, byteCount, hash)
        }
        XCTAssertEqual(appendLineReturned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abcDE\n")

        let rangedBuilder = makeBuilder("hello")
        let appendRangeReturned = withFlatString("WORLD") { data, length, byteCount, hash in
            kk_string_builder_appendRange_obj_flat(rangedBuilder, data, length, byteCount, hash, 1, 4)
        }
        XCTAssertEqual(appendRangeReturned, rangedBuilder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(rangedBuilder)), "helloORL")

        let insertRangeReturned = withFlatString("abcd") { data, length, byteCount, hash in
            kk_string_builder_insertRange_obj_flat(rangedBuilder, 1, data, length, byteCount, hash, 1, 3)
        }
        XCTAssertEqual(insertRangeReturned, rangedBuilder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(rangedBuilder)), "hbcelloORL")

        let setRangeReturned = withFlatString("XY") { data, length, byteCount, hash in
            kk_string_builder_setRange_flat(rangedBuilder, 1, 3, data, length, byteCount, hash)
        }
        XCTAssertEqual(setRangeReturned, rangedBuilder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(rangedBuilder)), "hXYelloORL")

        let replaceReturned = withFlatString("Z") { data, length, byteCount, hash in
            kk_string_builder_replace_obj_flat(rangedBuilder, 1, 3, data, length, byteCount, hash)
        }
        XCTAssertEqual(replaceReturned, rangedBuilder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(rangedBuilder)), "hZelloORL")
    }

    private func makeRuntimeString(_ value: String) -> Int {
        registerRuntimeObject(RuntimeStringBox(value))
    }

    private func makeBuilder(_ value: String) -> Int {
        withFlatString(value) { data, length, byteCount, hash in
            kk_string_builder_new_from_string_flat(data, length, byteCount, hash)
        }
    }

    private func withFlatString<T>(
        _ value: String,
        _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
    ) -> T {
        Array(value.utf8).withUnsafeBufferPointer { buffer in
            body(buffer.baseAddress, value.unicodeScalars.count, value.utf8.count, 0)
        }
    }

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }
}
